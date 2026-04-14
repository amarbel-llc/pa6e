pa6e(1)

# NAME

pa6e - send images to Peripage A6 thermal printers

# SYNOPSIS

*pa6e* *-m* _mac_ *-i* _image_ [*-p* _model_] [*-c* _level_] [*-f* _amount_]

# DESCRIPTION

*pa6e* sends a PNG image to a Peripage A6 or A6+ thermal printer over
Bluetooth. The image is resized to the printer's native width (384 pixels
for A6, 576 pixels for A6+), converted to 1-bit monochrome, and
transmitted as packed row data via RFCOMM.

The printer must already be paired with the host. *pa6e* connects using
the Bluetooth Serial Port Profile (BTSPP).

# OPTIONS

*-m* _mac_, *--mac* _mac_
	Bluetooth MAC address of the printer (e.g. AA:BB:CC:DD:EE:FF).
	Required.

*-i* _image_, *--image* _image_
	Path to a PNG image file. Required.

*-p* _model_, *--printer* _model_
	Printer model. Accepted values: *A6* (384px width, default) or
	*A6p* / *A6+* (576px width).

*-c* _level_, *--concentration* _level_
	Heat concentration level controlling print darkness. Values: *0*
	(light), *1* (medium, default), or *2* (dark).

*-f* _amount_, *--feed* _amount_
	Paper feed amount after printing, 0-255. Default: *120*. Controls
	how much blank paper is advanced after the image.

# EXIT STATUS

*0*
	Success.

*non-zero*
	An error occurred (invalid arguments, connection failure, or
	print error).

# EXAMPLES

Print an image to an A6 printer:

	pa6e -m AA:BB:CC:DD:EE:FF -i label.png

Print to an A6+ printer with maximum darkness:

	pa6e -m AA:BB:CC:DD:EE:FF -i label.png -p A6p -c 2

Light print with extra paper feed:

	pa6e -m AA:BB:CC:DD:EE:FF -i label.png -c 0 -f 200

# SEE ALSO

*pa6e-print*(1)
