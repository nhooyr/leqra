package main

import (
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestArenaCenterExcludesSurroundingUI(t *testing.T) {
	img := image.NewNRGBA(image.Rect(0, 0, 1400, 1000))
	draw.Draw(img, img.Bounds(), image.NewUniform(color.NRGBA{R: 17, A: 255}), image.Point{}, draw.Src)
	// Textured arena, a padded header rule, and true full-width arena borders.
	for y := 180; y < 860; y++ {
		img.SetNRGBA(700, y, color.NRGBA{G: 100, A: 255})
	}
	border := image.NewUniform(color.NRGBA{R: 52, G: 67, B: 74, A: 255})
	for _, rect := range []image.Rectangle{image.Rect(20, 80, 1380, 82), image.Rect(0, 178, 1400, 180), image.Rect(0, 860, 1400, 862)} {
		draw.Draw(img, rect, border, image.Point{}, draw.Src)
	}
	center, err := arenaCenter(img)
	if err != nil || center != image.Pt(700, 520) {
		t.Fatalf("center = %v, err = %v; want (700,520)", center, err)
	}
}

func TestMissingArenaRequiresExplicitCenter(t *testing.T) {
	if _, err := arenaCenter(image.NewNRGBA(image.Rect(0, 0, 1400, 1000))); err == nil {
		t.Fatal("blank image must not silently use the image center")
	}
}

func TestCropKeepsFullWidthAndCentersVertically(t *testing.T) {
	img := image.NewNRGBA(image.Rect(0, 0, 2048, 1200))
	for y := 0; y < 1200; y++ {
		for x := 0; x < 2048; x++ {
			img.SetNRGBA(x, y, color.NRGBA{R: uint8(x), G: uint8(y), B: uint8(x + y), A: 255})
		}
	}
	result, area, err := crop(img, image.Pt(1024, 600))
	if err != nil || area != (cropArea{100, 1100}) {
		t.Fatalf("area = %v, err = %v", area, err)
	}
	if result.Bounds() != image.Rect(0, 0, 1024, 500) {
		t.Fatalf("wrong output size: %v", result.Bounds())
	}
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			var r, g, b int
			for dy := 0; dy < 2; dy++ {
				for dx := 0; dx < 2; dx++ {
					pixel := img.NRGBAAt(x*2+dx, 100+y*2+dy)
					r += int(pixel.R)
					g += int(pixel.G)
					b += int(pixel.B)
				}
			}
			want := color.NRGBA{uint8((r + 2) / 4), uint8((g + 2) / 4), uint8((b + 2) / 4), 255}
			if result.NRGBAAt(x, y) != want {
				t.Fatalf("incorrect full-width sample at %d,%d: got %v, want %v", x, y, result.NRGBAAt(x, y), want)
			}
		}
	}
}

func TestFractionalResizePreservesAlphaAndPlayerCenter(t *testing.T) {
	img := image.NewNRGBA(image.Rect(0, 0, 3456, 2168))
	paint := color.NRGBA{R: 200, G: 50, B: 10, A: 128}
	draw.Draw(img, img.Bounds(), image.NewUniform(paint), image.Point{}, draw.Src)
	result, area, err := crop(img, image.Pt(1728, 1141))
	if err != nil || area != (cropArea{297.25, 1984.75}) {
		t.Fatalf("area = %v, err = %v", area, err)
	}
	for _, p := range []image.Point{{0, 0}, {1023, 0}, {512, 250}, {0, 499}, {1023, 499}} {
		if got := result.NRGBAAt(p.X, p.Y); got != paint {
			t.Fatalf("resizing changed a uniform translucent pixel at %v: %v", p, got)
		}
	}
}

func TestCropRejectsPadding(t *testing.T) {
	if _, _, err := crop(image.NewNRGBA(image.Rect(0, 0, 1024, 500)), image.Pt(512, 249)); err == nil {
		t.Fatal("off-center crop must fail instead of adding padding")
	}
}

func TestCropCannotShiftHorizontallyAndKeepFullWidth(t *testing.T) {
	if _, _, err := crop(image.NewNRGBA(image.Rect(0, 0, 1400, 1000)), image.Pt(600, 500)); err == nil {
		t.Fatal("an off-center X must not silently crop the sides or ignore the requested center")
	}
}

func TestInputOutputAliasesCannotOverwriteSource(t *testing.T) {
	absolute := filepath.Join(t.TempDir(), "showcase.png")
	want := []byte("source must stay unchanged")
	if err := os.WriteFile(absolute, want, 0644); err != nil {
		t.Fatal(err)
	}
	cwd, _ := os.Getwd()
	relative, err := filepath.Rel(cwd, absolute)
	if err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(t.TempDir(), "alias")
	if err = os.Symlink(filepath.Dir(absolute), alias); err != nil {
		t.Fatal(err)
	}
	for _, paths := range [][2]string{{relative, absolute}, {absolute, filepath.Join(alias, "showcase.png")}} {
		err = run([]string{"-input", paths[0], "-output", paths[1]})
		if err == nil || !strings.Contains(err.Error(), "different files") {
			t.Fatalf("expected alias rejection, got %v", err)
		}
	}
	got, err := os.ReadFile(absolute)
	if err != nil || string(got) != string(want) {
		t.Fatalf("source changed: %q, %v", got, err)
	}
}

func TestExplicitCenterForScreenshotWithoutBorders(t *testing.T) {
	dir := t.TempDir()
	input, output := filepath.Join(dir, "source.png"), filepath.Join(dir, "result.png")
	file, err := os.Create(input)
	if err != nil {
		t.Fatal(err)
	}
	if err = png.Encode(file, image.NewNRGBA(image.Rect(0, 0, 1300, 700))); err != nil {
		t.Fatal(err)
	}
	file.Close()
	if err = run([]string{"-input", input, "-output", output, "-center", "650,350"}); err != nil {
		t.Fatal(err)
	}
	result, err := os.Open(output)
	if err != nil {
		t.Fatal(err)
	}
	defer result.Close()
	config, err := png.DecodeConfig(result)
	if err != nil || config.Width != 1024 || config.Height != 500 {
		t.Fatalf("wrong output: %v, %v", config, err)
	}
}
