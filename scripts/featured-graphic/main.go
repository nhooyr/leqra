// Generate the fixed-size feature graphic from a full Showcase screenshot.
package main

import (
	"errors"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const width, height = 1024, 500

// P1 is centered in the arena, between the status bar and the loadout bar.
// Their full-width separator lines locate that center even when the amount
// of surrounding UI or the screenshot resolution changes.
func arenaCenter(img image.Image) (image.Point, error) {
	bounds := img.Bounds()
	type line struct{ start, end int }
	lines := make(map[color.RGBA][]line)
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		first := color.RGBAModel.Convert(img.At(bounds.Min.X, y)).(color.RGBA)
		uniform := true
		for x := bounds.Min.X + 1; x < bounds.Max.X; x++ {
			if color.RGBAModel.Convert(img.At(x, y)).(color.RGBA) != first {
				uniform = false
				break
			}
		}
		if !uniform {
			continue
		}
		runs := lines[first]
		if len(runs) > 0 && runs[len(runs)-1].end == y {
			runs[len(runs)-1].end++
		} else {
			runs = append(runs, line{y, y + 1})
		}
		lines[first] = runs
	}
	var best image.Rectangle
	for _, runs := range lines {
		for i := 1; i < len(runs); i++ {
			above, below := runs[i-1], runs[i]
			// Ignore broad background bands; arena separators are thin strokes.
			if above.end-above.start > 8 || below.end-below.start > 8 {
				continue
			}
			candidate := image.Rect(bounds.Min.X, above.end, bounds.Max.X, below.start)
			if candidate.Dy() >= bounds.Dy()/2 && candidate.Dy() > best.Dy() {
				best = candidate
			}
		}
	}
	if best.Empty() {
		return image.Point{}, errors.New("cannot locate the arena borders; specify -center X,Y for a cropped screenshot")
	}
	return image.Pt((best.Min.X+best.Max.X)/2, (best.Min.Y+best.Max.Y)/2), nil
}

type cropArea struct{ top, bottom float64 }

func crop(img image.Image, center image.Point) (*image.NRGBA, cropArea, error) {
	bounds := img.Bounds()
	if center.X != (bounds.Min.X+bounds.Max.X)/2 {
		return nil, cropArea{}, errors.New("keeping the full width requires the player to be horizontally centered")
	}
	scale := float64(bounds.Dx()) / width
	area := cropArea{float64(center.Y) - height*scale/2, float64(center.Y) + height*scale/2}
	if area.top < float64(bounds.Min.Y) || area.bottom > float64(bounds.Max.Y) {
		return nil, area, fmt.Errorf("source is too short for a %dx%d full-width crop centered at %v without padding", width, height, center)
	}
	result := image.NewNRGBA(image.Rect(0, 0, width, height))
	// Average each output pixel's source area, including fractional edge pixels.
	// Premultiplied samples prevent transparent pixels from tinting their neighbors.
	for y := 0; y < height; y++ {
		y0, y1 := area.top+float64(y)*scale, area.top+float64(y+1)*scale
		for x := 0; x < width; x++ {
			x0, x1 := float64(bounds.Min.X)+float64(x)*scale, float64(bounds.Min.X)+float64(x+1)*scale
			var red, green, blue, alpha, weight float64
			for sy := int(math.Floor(y0)); sy < int(math.Ceil(y1)); sy++ {
				wy := math.Min(y1, float64(sy+1)) - math.Max(y0, float64(sy))
				for sx := int(math.Floor(x0)); sx < int(math.Ceil(x1)); sx++ {
					w := wy * (math.Min(x1, float64(sx+1)) - math.Max(x0, float64(sx)))
					r, g, b, a := img.At(sx, sy).RGBA()
					red += float64(r) * w
					green += float64(g) * w
					blue += float64(b) * w
					alpha += float64(a) * w
					weight += w
				}
			}
			if alpha > 0 {
				result.SetNRGBA(x, y, color.NRGBA{
					R: uint8(math.Round(red / alpha * 255)),
					G: uint8(math.Round(green / alpha * 255)),
					B: uint8(math.Round(blue / alpha * 255)),
					A: uint8(math.Round(alpha / weight / 257)),
				})
			}
		}
	}
	return result, area, nil
}

func run(args []string) error {
	flags := flag.NewFlagSet("gen-featured-android.sh", flag.ContinueOnError)
	input := flags.String("input", "docs/showcase.png", "source Showcase PNG")
	output := flags.String("output", "docs/showcase-featured-android.png", "destination PNG")
	position := flags.String("center", "", "optional player center X,Y in source pixels")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected arguments; use -input, -output or -center X,Y")
	}
	inputPath, err := filepath.Abs(*input)
	if err != nil {
		return err
	}
	outputPath, err := filepath.Abs(*output)
	if err != nil {
		return err
	}
	if inputPath == outputPath {
		return errors.New("input and output must be different files")
	}
	if source, err := os.Stat(inputPath); err == nil {
		if destination, err := os.Stat(outputPath); err == nil && os.SameFile(source, destination) {
			return errors.New("input and output must be different files")
		}
	}
	file, err := os.Open(inputPath)
	if err != nil {
		return err
	}
	img, err := png.Decode(file)
	file.Close()
	if err != nil {
		return err
	}
	var center image.Point
	if *position == "" {
		center, err = arenaCenter(img)
	} else {
		parts := strings.Split(*position, ",")
		if len(parts) != 2 {
			return errors.New("center must be X,Y in source pixels")
		}
		center.X, err = strconv.Atoi(parts[0])
		if err == nil {
			center.Y, err = strconv.Atoi(parts[1])
		}
	}
	if err != nil {
		return err
	}
	result, area, err := crop(img, center)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(*output), 0755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(*output), ".featured-*.png")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	err = png.Encode(temporary, result)
	if err == nil {
		err = temporary.Chmod(0644)
	}
	closeErr := temporary.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err = os.Rename(temporary.Name(), *output); err != nil {
		return err
	}
	fmt.Printf("%s: %dx%d, full source width, player center %d,%d, source rows %.2f..%.2f\n", *output, width, height, center.X, center.Y, area.top, area.bottom)
	return nil
}

func main() {
	if err := run(os.Args[1:]); err != nil && !errors.Is(err, flag.ErrHelp) {
		fmt.Fprintln(os.Stderr, "gen-featured-android.sh:", err)
		os.Exit(1)
	}
}
