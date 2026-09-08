package main

// A bounded, text-only RFC 6455 server transport. No extensions or compression
// are negotiated. It accepts fragmented UTF-8 text and interleaved control
// frames, requires client masking, and bounds BOTH frames and full messages.
// Keeping this separate from rooms/physics makes it replaceable independently.

import (
	"bufio"
	"crypto/sha1" // Required by the WebSocket handshake; not used for authentication.
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// Accommodates escaped-Unicode chat and eight-seat preset payloads, still bounded.
const maxMessage = 8192
const wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

type wsConn struct {
	conn        net.Conn
	reader      *bufio.Reader
	writeMu     sync.Mutex
	closeOnce   sync.Once
	fragmented  bool
	message     []byte
	frameWindow time.Time
	frames      int
}

type wsError struct {
	code   uint16
	reason string
}

func (e *wsError) Error() string        { return e.reason }
func protocolError(reason string) error { return &wsError{1002, reason} }

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

func upgradeWS(w http.ResponseWriter, r *http.Request, allowed []string) (*wsConn, error) {
	fail := func(status int, msg string) (*wsConn, error) { http.Error(w, msg, status); return nil, errors.New(msg) }
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
	hj, ok := w.(http.Hijacker)
	if !ok {
		return fail(500, "WebSocket upgrade unavailable")
	}
	conn, rw, err := hj.Hijack()
	if err != nil {
		return nil, err
	}
	sum := sha1.Sum([]byte(key + wsGUID))
	accept := base64.StdEncoding.EncodeToString(sum[:])
	_ = conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	_, err = fmt.Fprintf(rw, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n", accept)
	if err == nil {
		err = rw.Flush()
	}
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	_ = conn.SetWriteDeadline(time.Time{})
	_ = conn.SetReadDeadline(time.Now().Add(35 * time.Second))
	return &wsConn{conn: conn, reader: rw.Reader, frameWindow: time.Now()}, nil
}

func (c *wsConn) close() { c.closeOnce.Do(func() { _ = c.conn.Close() }) }
func (c *wsConn) writeFrame(op byte, payload []byte) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_ = c.conn.SetWriteDeadline(time.Now().Add(3 * time.Second))
	h := []byte{0x80 | op}
	n := len(payload)
	if n < 126 {
		h = append(h, byte(n))
	} else if n <= 65535 {
		h = append(h, 126, byte(n>>8), byte(n))
	} else {
		h = append(h, 127)
		var b [8]byte
		binary.BigEndian.PutUint64(b[:], uint64(n))
		h = append(h, b[:]...)
	}
	// net.Buffers handles short writes and avoids copying large state packets.
	bufs := net.Buffers{h, payload}
	_, err := bufs.WriteTo(c.conn)
	return err
}
func (c *wsConn) writeClose(code uint16, reason string) {
	if len(reason) > 120 {
		reason = "Connection closed"
	}
	p := make([]byte, 2, len(reason)+2)
	binary.BigEndian.PutUint16(p, code)
	p = append(p, reason...)
	_ = c.writeFrame(8, p)
}
func validCloseCode(code uint16) bool {
	return (code >= 1000 && code <= 1014 && code != 1004 && code != 1005 && code != 1006) || (code >= 3000 && code <= 4999)
}
func (c *wsConn) readMessage() ([]byte, error) {
	for {
		var h [2]byte
		if _, err := io.ReadFull(c.reader, h[:]); err != nil {
			return nil, err
		}
		now := time.Now()
		if now.Sub(c.frameWindow) >= time.Second {
			c.frameWindow = now
			c.frames = 0
		}
		c.frames++
		if c.frames > 180 {
			return nil, &wsError{1008, "Too many frames"}
		}
		fin := h[0]&0x80 != 0
		op := h[0] & 0x0f
		if h[0]&0x70 != 0 || h[1]&0x80 == 0 {
			return nil, protocolError("Invalid frame flags or missing mask")
		}
		if op != 0 && op != 1 && op != 2 && op != 8 && op != 9 && op != 10 {
			return nil, protocolError("Unknown opcode")
		}
		n := uint64(h[1] & 0x7f)
		if op >= 8 && (!fin || n > 125) {
			return nil, protocolError("Invalid control frame")
		}
		switch n {
		case 126:
			var b [2]byte
			if _, err := io.ReadFull(c.reader, b[:]); err != nil {
				return nil, err
			}
			n = uint64(binary.BigEndian.Uint16(b[:]))
			if n < 126 {
				return nil, protocolError("Non-minimal length")
			}
		case 127:
			var b [8]byte
			if _, err := io.ReadFull(c.reader, b[:]); err != nil {
				return nil, err
			}
			n = binary.BigEndian.Uint64(b[:])
			if b[0]&0x80 != 0 || n < 65536 {
				return nil, protocolError("Invalid extended length")
			}
		}
		if n > maxMessage || (op < 8 && n+uint64(len(c.message)) > maxMessage) {
			return nil, &wsError{1009, "Message too large"}
		}
		var mask [4]byte
		if _, err := io.ReadFull(c.reader, mask[:]); err != nil {
			return nil, err
		}
		data := make([]byte, int(n))
		if _, err := io.ReadFull(c.reader, data); err != nil {
			return nil, err
		}
		for i := range data {
			data[i] ^= mask[i%4]
		}
		switch op {
		case 8:
			if len(data) == 1 {
				return nil, protocolError("Invalid close frame")
			}
			if len(data) >= 2 {
				if !validCloseCode(binary.BigEndian.Uint16(data[:2])) {
					return nil, protocolError("Invalid close code")
				}
				if !utf8.Valid(data[2:]) {
					return nil, &wsError{1007, "Invalid close reason"}
				}
			}
			_ = c.writeFrame(8, data)
			return nil, io.EOF
		case 9:
			if err := c.writeFrame(10, data); err != nil {
				return nil, err
			}
			continue
		case 10:
			_ = c.conn.SetReadDeadline(time.Now().Add(35 * time.Second))
			continue
		case 2:
			return nil, &wsError{1003, "Only JSON text is supported"}
		case 1:
			if c.fragmented {
				return nil, protocolError("Nested fragmented message")
			}
			c.message = data
			c.fragmented = !fin
		case 0:
			if !c.fragmented {
				return nil, protocolError("Unexpected continuation")
			}
			c.message = append(c.message, data...)
			c.fragmented = !fin
		}
		if !fin {
			continue
		}
		data = c.message
		c.message = nil
		if !utf8.Valid(data) {
			return nil, &wsError{1007, "Invalid UTF-8"}
		}
		_ = c.conn.SetReadDeadline(time.Now().Add(35 * time.Second))
		return data, nil
	}
}
