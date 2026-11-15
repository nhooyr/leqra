package main

// Game messages use coder/websocket for the RFC 6455 handshake, framing,
// fragmentation, control frames and independently compressed messages. The
// wrapper retains leqra's origin, message, rate and connection-liveness policy.
import (
	"bufio"
	"compress/flate"
	"context"
	"encoding/base64"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode/utf8"

	"github.com/coder/websocket"
)

// Accommodates escaped-Unicode chat and eight-seat preset payloads, still bounded.
const maxMessage = 8192
const maxTransportMessagesPerSecond = 220 // Two input streams plus control messages.
const wsReadTimeout = 35 * time.Second
const wsWriteTimeout = 3 * time.Second
const wsInboundBytesPerSecond = 256 << 10
const wsInboundByteBurst = 512 << 10

type wsConn struct {
	conn          net.Conn // Deadlines and forced shutdown; websocket owns all wire IO.
	socket        *websocket.Conn
	closeOnce     sync.Once
	messageWindow time.Time
	messages      int
	rateMu        sync.Mutex
	rateExceeded  atomic.Bool
	openedAt      time.Time
	lastPeerRead  atomic.Int64 // Nanoseconds since openedAt, including WebSocket pongs.
}

type wsError struct {
	code   uint16
	reason string
}

func (e *wsError) Error() string { return e.reason }

// List-valued HTTP headers can span several field lines.
func headerToken(values []string, token string) bool {
	for _, value := range values {
		for _, s := range strings.Split(value, ",") {
			if strings.EqualFold(strings.TrimSpace(s), token) {
				return true
			}
		}
	}
	return false
}

func validOrigin(r *http.Request, allowed []string) bool {
	// Missing/opaque origins are not browser game clients. Requiring one also
	// avoids accidentally enabling cross-site WebSocket hijacking.
	origin := r.Header.Get("Origin")
	u, err := url.Parse(origin)
	if err != nil || u.User != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || (u.Path != "" && u.Path != "/") || u.RawQuery != "" || u.Fragment != "" {
		return false
	}
	if strings.EqualFold(u.Host, r.Host) {
		return true
	}
	for _, a := range allowed {
		if strings.EqualFold(strings.TrimRight(origin, "/"), a) {
			return true
		}
	}
	return false
}

func validateUpgrade(w http.ResponseWriter, r *http.Request, allowed []string) (string, error) {
	fail := func(status int, msg string) (string, error) { http.Error(w, msg, status); return "", errors.New(msg) }
	if r.Method != http.MethodGet || !headerToken(r.Header.Values("Connection"), "upgrade") || !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		return fail(400, "WebSocket upgrade required")
	}
	if r.Header.Get("Sec-WebSocket-Version") != "13" {
		w.Header().Set("Sec-WebSocket-Version", "13")
		return fail(426, "WebSocket version 13 required")
	}
	if !validOrigin(r, allowed) {
		return fail(403, "Origin not allowed")
	}
	key := r.Header.Get("Sec-WebSocket-Key")
	raw, err := base64.StdEncoding.DecodeString(key)
	if err != nil || len(raw) != 16 {
		return fail(400, "Invalid WebSocket key")
	}
	return key, nil
}

// Capture the accepted connection only for deadlines and immediate shutdown.
// The library performs every handshake and frame read/write.
type socketResponseWriter struct {
	http.ResponseWriter
	conn net.Conn
}

func (w *socketResponseWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	conn, rw, err := http.NewResponseController(w.ResponseWriter).Hijack()
	if err != nil {
		return nil, nil, err
	}
	// A byte budget bounds floods of empty continuation frames without keeping
	// a second WebSocket parser. Include bytes buffered during the HTTP upgrade.
	guarded := &socketByteBudget{Conn: conn, at: time.Now(), available: wsInboundByteBurst - float64(rw.Reader.Buffered())}
	w.conn = guarded
	return guarded, rw, nil
}

type socketByteBudget struct {
	net.Conn
	at        time.Time
	available float64
}

func (c *socketByteBudget) allowance(now time.Time) int {
	c.available = min(wsInboundByteBurst, c.available+max(0, now.Sub(c.at).Seconds())*wsInboundBytesPerSecond)
	c.at = now
	return int(c.available)
}

func (c *socketByteBudget) Read(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	n := c.allowance(time.Now())
	if n == 0 {
		return 0, &wsError{1008, "Inbound byte rate exceeded"}
	}
	count, err := c.Conn.Read(p[:min(n, len(p))])
	c.available -= float64(count)
	return count, err
}

func upgradeWS(w http.ResponseWriter, r *http.Request, deflate bool) (*wsConn, error) {
	now := time.Now()
	c := &wsConn{messageWindow: now, openedAt: now}
	writer := &socketResponseWriter{ResponseWriter: w}
	opts := websocket.AcceptOptions{
		// serveSocket already enforces exact origins, including rejecting missing
		// origins and URL paths which the library's host patterns do not reject.
		InsecureSkipVerify:   true,
		CompressionThreshold: 1024,
		OnPingReceived: func(context.Context, []byte) bool {
			return c.controlReceived()
		},
		OnPongReceived: func(context.Context, []byte) {
			c.controlReceived()
		},
	}
	if deflate {
		opts.CompressionMode = websocket.CompressionNoContextTakeover
	}
	socket, err := websocket.Accept(writer, r, &opts)
	if err != nil {
		return nil, err
	}
	c.conn, c.socket = writer.conn, socket
	socket.SetReadLimit(maxMessage)
	c.refreshReadDeadline()
	return c, nil
}

func (c *wsConn) close() {
	c.closeOnce.Do(func() {
		// Close the underlying connection first so even a concurrent library
		// close handshake or blocked writer ends immediately.
		if c.conn != nil {
			_ = c.conn.Close()
		}
		if c.socket != nil {
			_ = c.socket.CloseNow()
		}
	})
}

func (c *wsConn) refreshReadDeadline() {
	now := time.Now()
	c.lastPeerRead.Store(int64(now.Sub(c.openedAt)))
	_ = c.conn.SetReadDeadline(now.Add(wsReadTimeout))
}

func (c *wsConn) peerReadRecently(now time.Time, limit time.Duration) bool {
	return now.Sub(c.openedAt)-time.Duration(c.lastPeerRead.Load()) < limit
}

func (c *wsConn) countMessage() bool {
	c.rateMu.Lock()
	defer c.rateMu.Unlock()
	now := time.Now()
	if now.Sub(c.messageWindow) >= time.Second {
		c.messageWindow, c.messages = now, 0
	}
	c.messages++
	return c.messages <= maxTransportMessagesPerSecond
}

func (c *wsConn) controlReceived() bool {
	if !c.countMessage() {
		c.rateExceeded.Store(true)
		// End the current Reader outside its control callback. The read loop
		// then sends one bounded close handshake after releasing the read lock.
		_ = c.conn.SetReadDeadline(time.Now())
		return false
	}
	c.refreshReadDeadline()
	return true
}

func (c *wsConn) writeText(payload []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), wsWriteTimeout)
	defer cancel()
	return c.socket.Write(ctx, websocket.MessageText, payload)
}

func (c *wsConn) ping() error {
	ctx, cancel := context.WithTimeout(context.Background(), wsWriteTimeout)
	defer cancel()
	return c.socket.Ping(ctx)
}

func (c *wsConn) writeClose(code uint16, reason string) {
	if len(reason) > 120 {
		reason = "Connection closed"
	}
	// Bound the library's graceful handshake even if the peer stops reading.
	_ = c.conn.SetDeadline(time.Now().Add(wsWriteTimeout))
	_ = c.socket.Close(websocket.StatusCode(code), reason)
}

func (c *wsConn) readMessage() ([]byte, error) {
	return c.readMessageWithTimeout(wsReadTimeout)
}

func (c *wsConn) readMessageWithTimeout(messageTimeout time.Duration) ([]byte, error) {
	kind, reader, err := c.socket.Reader(context.Background())
	if err != nil {
		if c.rateExceeded.Load() {
			return nil, &wsError{1008, "Too many transport messages"}
		}
		return nil, transportReadError(err)
	}
	// Pongs keep an idle menu alive, but cannot extend one incomplete
	// fragmented message indefinitely.
	timeout := time.AfterFunc(messageTimeout, c.close)
	defer timeout.Stop()
	if kind != websocket.MessageText {
		return nil, &wsError{1003, "Only JSON text is supported"}
	}
	data, err := io.ReadAll(reader)
	if err != nil {
		if c.rateExceeded.Load() {
			return nil, &wsError{1008, "Too many transport messages"}
		}
		return nil, transportReadError(err)
	}
	if c.rateExceeded.Load() || !c.countMessage() {
		return nil, &wsError{1008, "Too many transport messages"}
	}
	if !utf8.Valid(data) {
		return nil, &wsError{1007, "Invalid UTF-8"}
	}
	c.refreshReadDeadline()
	return data, nil
}

func transportReadError(err error) error {
	var policy *wsError
	var network net.Error
	if errors.As(err, &policy) || errors.As(err, &network) || errors.Is(err, net.ErrClosed) || errors.Is(err, io.EOF) || websocket.CloseStatus(err) >= 0 {
		return err
	}
	if errors.Is(err, websocket.ErrMessageTooBig) {
		return &wsError{1009, "Message too large"}
	}
	var corrupt flate.CorruptInputError
	if errors.As(err, &corrupt) {
		return &wsError{1007, "Invalid compressed message"}
	}
	return &wsError{1002, "Invalid WebSocket message"}
}
