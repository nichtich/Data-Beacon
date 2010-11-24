use 5.8.2;
use strict;
use ExtUtils::MakeMaker;

&WriteMakefile(
    NAME            => 'Data::Beacon',
    DISTNAME        => 'Data-Beacon',
    VERSION_FROM    => 'lib/Data/Beacon.pm',
    ABSTRACT_FROM   => 'lib/Data/Beacon.pm',
    PMLIBDIRS       => [ qw( lib/ ) ],
    AUTHOR          => 'Jakob Voss <jakob.voss@gbv.de>',
    PREREQ_PM       => {
        'Getopt::Long' => '0',
        'Pod::Usage' => '0',
        'Data::Validate::URI' => 0,
        'Time::Piece' => 0,
        'Scalar::Util' => 0,
    },
    dist            => {
        COMPRESS => 'gzip -9f',
        SUFFIX => 'gz',
    },
    depend          => {
        Makefile => '$(VERSION_FROM)'
    },
    EXE_FILES       => [ 'bin/beacon' ],
    LICENSE         => 'perl',
    META_MERGE => {
        resources => {
            license => 'http://dev.perl.org/licenses/',
            homepage => 'http://github.com/nichtich/p5-data-beacon',
            bugtracker => 'http://github.com/nichtich/p5-data-beacon/issues',
            repository => 'http://github.com/toddr/p5-data-beacon',
        }
    }
);
