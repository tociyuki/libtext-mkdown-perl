use strict;
use warnings;
use Test::More tests => 2;

use_ok( 'Text::Mkdown' );

my $m     = Text::Mkdown->new;
my $html1 = $m->markdown('<a+b@c.org>');
like( $html1, qr/<p><a href=".+&#.+">.+&#.+<\/a><\/p>/ );

