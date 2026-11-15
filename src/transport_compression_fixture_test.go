package main

import (
	"bytes"
	"compress/flate"
	"io"
	"sync"
)

const wsCompressed = 0x40

type compressedFixtureFrame struct {
	data       []byte
	compressed bool
}

// Raw client fixtures need independent compressed payloads; production compression
// and inflation belong exclusively to coder/websocket.
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

// Build independent raw client payloads for compressed-input boundary tests.
func compressSnapshot(data []byte) compressedFixtureFrame {
	if len(data) < 1024 {
		return compressedFixtureFrame{data: data}
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
		return compressedFixtureFrame{data: encoded[:len(encoded)-len(deflateSyncTail)], compressed: true}
	}
	return compressedFixtureFrame{data: data}
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
