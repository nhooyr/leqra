package main

import (
	"bytes"
	"compress/flate"
	"io"
	"strconv"
	"strings"
	"sync"
)

// Use the RFC 7692 extension without a shared dictionary in either direction.
// An unsupported offer falls back to ordinary JSON text frames.
func acceptsSnapshotDeflate(values []string) bool {
	for _, value := range values {
		for _, offer := range strings.Split(value, ",") {
			parts := strings.Split(offer, ";")
			if strings.TrimSpace(parts[0]) == "permessage-deflate" && validDeflateOffer(parts[1:]) {
				return true
			}
		}
	}
	return false
}

func validDeflateOffer(params []string) bool {
	seen := make(map[string]bool, len(params))
	for _, param := range params {
		name, value, assigned := strings.Cut(param, "=")
		name = strings.TrimSpace(name)
		if seen[name] {
			return false
		}
		seen[name] = true
		switch name {
		case "server_no_context_takeover", "client_no_context_takeover":
			if assigned {
				return false
			}
		case "client_max_window_bits":
			// The offer is a hint, so the reply need not include this parameter.
			if assigned {
				value = strings.TrimSpace(value)
				if len(value) >= 2 && value[0] == '"' && value[len(value)-1] == '"' {
					value = value[1 : len(value)-1]
				}
				bits, err := strconv.Atoi(value)
				if err != nil || bits < 8 || bits > 15 || strconv.Itoa(bits) != value {
					return false
				}
			}
		default:
			// The standard flate writer cannot guarantee a smaller server window.
			return false
		}
	}
	return true
}

type snapshotFrame struct {
	data       []byte
	compressed bool
}

type snapshotCompressor struct {
	out    bytes.Buffer
	writer *flate.Writer
}

var snapshotCompressors = sync.Pool{New: func() any {
	z := new(snapshotCompressor)
	z.writer, _ = flate.NewWriter(&z.out, flate.BestSpeed)
	return z
}}

const deflateSyncTail = "\x00\x00\xff\xff"
const deflateFinalBlock = "\x01\x00\x00\xff\xff"

// Each snapshot is independently decodable even if the socket replaces a
// pending snapshot. Reliable traffic (including private room tokens) stays raw.
func compressSnapshot(data []byte) snapshotFrame {
	if len(data) < 1024 {
		return snapshotFrame{data: data}
	}
	z := snapshotCompressors.Get().(*snapshotCompressor)
	z.out.Grow(len(data) / 3) // Reserve enough for typical compressed snapshots in one allocation.
	z.writer.Reset(&z.out)
	_, _ = z.writer.Write(data)
	_ = z.writer.Flush()
	encoded := z.out.Bytes()
	z.out = bytes.Buffer{} // Transfer ownership before returning to the pool.
	snapshotCompressors.Put(z)
	if len(encoded) >= len(deflateSyncTail) && len(encoded)-len(deflateSyncTail) < len(data) {
		return snapshotFrame{data: encoded[:len(encoded)-len(deflateSyncTail)], compressed: true}
	}
	return snapshotFrame{data: data}
}

type messageInflater struct {
	source bytes.Reader
	reader io.ReadCloser
}

var messageInflaters = sync.Pool{New: func() any {
	z := new(messageInflater)
	z.reader = flate.NewReader(&z.source)
	return z
}}

func inflateMessage(data []byte, limit int64) ([]byte, error) {
	z := messageInflaters.Get().(*messageInflater)
	// Restore the empty sync-flush block and add a final empty block so the
	// flate reader reports EOF instead of mistaking a valid flush for truncation.
	z.source.Reset(append(data, deflateSyncTail+deflateFinalBlock...))
	_ = z.reader.(flate.Resetter).Reset(&z.source, nil)
	decoded, err := io.ReadAll(io.LimitReader(z.reader, limit+1))
	z.source.Reset(nil)
	messageInflaters.Put(z)
	if int64(len(decoded)) > limit {
		return nil, &wsError{1009, "Message too large"}
	}
	if err != nil {
		return nil, &wsError{1007, "Invalid compressed message"}
	}
	return decoded, nil
}
