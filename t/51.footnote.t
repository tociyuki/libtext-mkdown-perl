use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

require "$Bin/21.fulldocs-text-markdown.t";

my $docsdir = "$Bin/docs-php-markdown-extra";
my @files = qw(Footnotes);

plan tests => scalar(@files) + 1;

use_ok('Text::Mkdown');

my $m = Text::Mkdown->new();

run_tests($m, $docsdir, @files);

