pa6e-print(1)

# NAME

pa6e-print - convert markdown to thermal printer images

# SYNOPSIS

*pa6e-print* _file_ [_mac_] [_model_] [_concentration_]

# DESCRIPTION

*pa6e-print* converts a Markdown file into a trimmed PNG image sized for
Peripage A6 thermal printers. If a Bluetooth MAC address is provided, the
image is sent to the printer automatically.

The conversion pipeline has four stages:

. *pandoc* converts Markdown to standalone HTML, embedding _peri-a6.css_
  (a print stylesheet using the Azuro TF font, applied via @media print).
. *html-to-pdf* renders HTML to PDF using headless Chromium with 57mm
  (2.2409in) paper width and zero side margins.
. *imagemagick* rasterizes the PDF to PNG at the printer's native
  resolution, then trims whitespace using a North-gravity splice+chop
  technique.
. If _mac_ is provided, *pa6e*(1) sends the trimmed image to the printer.

The final image is written to _file_*-trimmed.png*.

# OPTIONS

_file_
	Path to the Markdown source file. Required.

_mac_
	Bluetooth MAC address of the printer (e.g. AA:BB:CC:DD:EE:FF). If
	omitted, only the image is generated (no printing).

_model_
	Printer model: *A6* (384px, default) or *A6p* / *A6+* (576px).

_concentration_
	Heat concentration level: *0* (light), *1* (medium), or *2* (dark,
	default).

# EXIT STATUS

*0*
	Success.

*non-zero*
	A pipeline stage failed.

# ENVIRONMENT

*PATH*
	Must include *chromium* or *google-chrome-stable*. Chromium is not
	packaged by the nix flake and must be available at runtime.

# FILES

_peri-a6.css_
	Print stylesheet embedded into the HTML. Uses the Azuro TF font and
	is only applied via @media print. Located alongside the script in the
	nix store or repository root.

# EXAMPLES

Generate an image without printing:

	pa6e-print label.md

Generate and print to an A6 printer:

	pa6e-print label.md AA:BB:CC:DD:EE:FF

Print to an A6+ printer with maximum darkness:

	pa6e-print label.md AA:BB:CC:DD:EE:FF A6p 2

# SEE ALSO

*pa6e*(1), *pandoc*(1), *chromium*(1)
