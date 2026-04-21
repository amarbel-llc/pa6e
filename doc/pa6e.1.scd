pa6e(1)

# NAME

pa6e - Peripage A6 thermal printer toolset

# SYNOPSIS

*pa6e send* *-m* _mac_ *-i* _image_ [*-p* _model_] [*-c* _level_] [*-f* _amount_]

*pa6e print* _file_ [*-m* _mac_] [*-p* _model_] [*-c* _level_] [*-f* _amount_] [*--css* _path_]

# DESCRIPTION

*pa6e* is a toolset for Peripage A6 and A6+ thermal printers. It has two
subcommands:

*send* sends a pre-rendered PNG image to the printer over Bluetooth.

*print* converts a Markdown file into a trimmed PNG image sized for the
printer. If a Bluetooth MAC address is provided, the image is also sent
to the printer.

The *print* pipeline has four stages:

. *pandoc* converts Markdown to standalone HTML, embedding _peri-a6.css_
  (a print stylesheet using the Azuro TF font, applied via @media print).
. *chrest* renders HTML to PDF using headless Firefox with 57mm
  (2.2409in) paper width and zero side margins.
. *imagemagick* rasterizes the PDF to PNG at the printer's native
  resolution, then trims whitespace using a North-gravity splice+chop
  technique.
. If _mac_ is provided, the trimmed image is sent to the printer via
  Bluetooth RFCOMM.

The final image is written to _file_*-trimmed.png*.

# SEND OPTIONS

*-m* _mac_, *--mac* _mac_
	Bluetooth MAC address of the printer (e.g. AA:BB:CC:DD:EE:FF).
	Required.

*-i* _image_, *--image* _image_
	Path to a PNG image file. Required.

*-p* _model_, *--printer* _model_
	Printer model. Accepted values: *A6* (384px width, default) or
	*A6p* / *A6+* (576px width).

*-c* _level_, *--concentration* _level_
	Heat concentration level: *0* (light), *1* (medium, default), or
	*2* (dark).

*-f* _amount_, *--feed* _amount_
	Paper feed amount after printing, 0-255. Default: *120*.

# PRINT OPTIONS

_file_
	Path to the Markdown source file. Required (positional argument).

*-m* _mac_, *--mac* _mac_
	Bluetooth MAC address of the printer. If omitted, only the image
	is generated (no printing).

*-p* _model_, *--printer* _model_
	Printer model: *A6* (384px) or *A6p* / *A6+* (576px, default).

*-c* _level_, *--concentration* _level_
	Heat concentration level: *0* (light), *1* (medium), or *2*
	(dark, default).

*-f* _amount_, *--feed* _amount_
	Paper feed amount after printing, 0-255. Default: *120*.

*--css* _path_
	Path to a CSS stylesheet. Overrides the built-in path set at
	build time. Falls back to _peri-a6.css_ in the working directory.

# EXIT STATUS

*0*
	Success.

*non-zero*
	An error occurred (invalid arguments, pipeline failure, connection
	failure, or print error).

# EXAMPLES

Generate a printer image without printing:

	pa6e print label.md

Generate and print to an A6+ printer:

	pa6e print label.md -m AA:BB:CC:DD:EE:FF

Print with maximum darkness:

	pa6e print label.md -m AA:BB:CC:DD:EE:FF -c 2

Send a pre-rendered image to the printer:

	pa6e send -m AA:BB:CC:DD:EE:FF -i label-trimmed.png -p A6p -c 2

# SEE ALSO

*pandoc*(1), *chrest*(1), *magick*(1)
