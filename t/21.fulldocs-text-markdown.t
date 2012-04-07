use strict;
use warnings;
use Test::More;
use Test::Differences;
use FindBin qw($Bin);
use Encode;

### Actual code for this test - unless(caller) stops it
### being run when this file is required by other tests

unless (caller) {
    my $docsdir = "$Bin/Text-Markdown.mdtest";
    my @files = get_files($docsdir);

    plan tests => scalar(@files) + 1;

    use_ok('Text::Mkdown');

    my $m = Text::Mkdown->new();

    run_tests($m, $docsdir, @files);
}

sub get_files {
    my ($docsdir) = @_;
    my $DH;
    opendir($DH, $docsdir) or die("Could not open $docsdir");
    my %files = map { s/\.(xhtml|html|text)$// ? ($_ => 1) : (); } readdir($DH);
    closedir($DH);
    return sort keys %files;
}

sub slurp {
    my ($filename) = @_;
    open my $file, '<', $filename or die "Couldn't open $filename: $!";
    local $/ = undef;
    return <$file>;
}    

sub run_tests {
    my ($m, $docsdir, @files) = @_;
    foreach my $test (@files) {
        run_test($m, $docsdir, $test);
    }
}

sub run_test {
    my ($m, $docsdir, $test) = @_;
    my ($input, $output);
    eval {
        if (-f "$docsdir/$test.html") {
            $output = slurp("$docsdir/$test.html");
        }
        else {
            $output = slurp("$docsdir/$test.xhtml");
        }
        $input  = slurp("$docsdir/$test.text");
    };
    $input .= "\n\n";
    $output .= "\n\n";
    if ($@) {
        fail("1 part of test file not found: $@");
        next;
    }
    $output =~ s/\s+\z//; # trim trailing whitespace
    my $processed = encode('UTF-8', $m->markdown(decode('UTF-8', $input)));
    $processed =~ s/\s+\z//; # trim trailing whitespace

    # Un-comment for debugging if you have space diffs you can't see..
    #$output =~ s/ /&nbsp;/g;
    #$output =~ s/\t/&tab;/g;
    #$processed =~ s/ /&nbsp;/g;
    #$processed =~ s/\t/&tab;/g;
    
    if (0 <= index $test, 'todo') {
        TODO: {
            local $TODO = 'Have not fixed a load of the bugs PHP markdown has yet.';
            unified_diff;
            eq_or_diff $processed, $output, "Docs test: $test";
        };
    }
    else {
        unified_diff;
        eq_or_diff $processed, $output, "Docs test: $test";
    }
}

1;
