use strict;
use warnings;
use Text::Mkdown;
use Test::More tests => 1;

my $txt =  Text::Mkdown->new->markdown(<<'END_MARKDOWN');
This is a para.

    This is code.
    ---
    This is code.

This is a para.
END_MARKDOWN

unlike($txt, qr{<hr}, "no HR elements when the hr is in a code block");
