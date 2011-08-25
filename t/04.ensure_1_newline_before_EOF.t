use strict;
use warnings;
use Test::More tests => 3;
use Test::Differences;

use_ok 'Text::Mkdown';
my $m = Text::Mkdown->new();
my ($out, $expected);

unified_diff;

$out = $m->markdown("foo\n\n\n");
eq_or_diff($out, "<p>foo</p>\n", "collapse multiple newlines at EOF into one");

$out = $m->markdown("foo");
eq_or_diff($out, "<p>foo</p>\n", "ensure newline before EOF");

