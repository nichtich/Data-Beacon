# NAME

Data::Beacon - BEACON format parser and serializer

# DESCRIPTION

This Perl 5 module provides a class to parse and serialize BEACON link dump
format. See <http://github.com/gbv/beaconspec> for a current specification

The module includes a command line script named `beacon`.

# INSTALLATION

You can either get releases from CPAN, or get the latest development
version from github at http://github.com/nichtich/p5-data-beacon. 

To manually install from the sources, best use `cpanm`:

    $ cpanm Data::Beacon

# BUGS

The current version of this module does not fully reflect the BEACON
specification. Please do not use it for serious applications unless
BEACON has been finalized!

Please report any bugs or feature requests to this project's GitHub
repository at:

http://github.com/nichtich/p5-data-beacon/issues

Thank you!   

# AUTHOR
Jakob Voss <jakob.voss@gbv.de>

# LICENSE

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.8 or, at
your option, any later version of Perl 5 you may have available.

In addition you may fork this library under the terms of the 
GNU Affero General Public License.
