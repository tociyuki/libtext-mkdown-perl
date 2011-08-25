use strict;
use warnings;
use Test::More tests => 2;

# http://babelmark.bobtfish.net/?markdown=x%3Cmax(a%2Cb)%0D%0A&normalize=on

use_ok('Text::Mkdown');

my $m = Text::Mkdown->new;

my $in = q{x<max(a,b)};
my $ex = qq{<p>x&lt;max(a,b)</p>\n};

{
    #local $TODO = 'Known "bug" (the no < unless next to space thing was originally by design) - but I would like to
#break the spec and fix this..';
    is ($m->markdown($in), $ex);
};
