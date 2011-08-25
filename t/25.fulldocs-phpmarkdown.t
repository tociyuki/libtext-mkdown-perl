use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

require "$Bin/21.fulldocs-text-markdown.t";

my $docsdir = "$Bin/PHP_Markdown-from-MDTest1.1.mdtest";
my @files = get_files($docsdir);

plan tests => scalar(@files) + 1;

use_ok('Text::Mkdown');

my $m = Text::Mkdown->new();

run_tests($m, $docsdir, @files);

