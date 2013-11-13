package Text::Mkdown;
use strict;
use warnings;
use 5.008001;
use Carp;
use Encode;
use parent qw(Exporter);

our $VERSION = '0.015';
# $Id$

our @EXPORT_OK = qw(markdown);

my $ALNUM = 'A-Za-z0-9';
my $ALPHA = 'A-Za-z';
my $LOWER = 'a-z';
my $DIGIT = '0-9';
my $XDIGIT = '0-9A-Fa-f';
my $TAB = qr/(?:\t|[ ](?:\t|[ ](?:\t|[ ][ \t])))/msx;
my $PAD = qr/[ ]{0,3}/msx;
my $WS = qr/[ \t]/msx;
my $NEST_PAREN = _nest_pattern(q{[^()\\n]*?(?:[(]R[)][^()\\n]*?)*}, 6);
my $NEST_BRACKET = _nest_pattern(q{[^\\[\\]]*(?:\\[R\\][^\\[\\]]*)*}, 6);
my $BLOCKTAG = qr{
    blockquote|d(?:el|iv|l)|f(?:i(?:eldset|gure)|orm)|h[1-6]|i(?:frame|ns)
    |math|noscript|ol|p(?:re)?|script|table|ul
}msx;
my $HTML5_NAME = qr/[$ALPHA][-_:$ALNUM]*/msx;
my $HTML5_ATTR = qr{
    (?: [ \t\n]+
        $HTML5_NAME
        (?: [ \t\n]* [=] [ \t\n]*
            (?:"[^"]*"|'[^']*'|`[^`]*`|[^\P{Graph}<>"'`=]+) )? )*
}msx;
my $HTML5_TAG = qr{
    <   (?: $HTML5_NAME $HTML5_ATTR [ \t\n]* /?>
        |   / $HTML5_NAME [ \t\n]* >
        |   !-- .*? -->
        )
}msx;
my %HTML5_SPECIAL = (
    q(&) => '&amp;', q(<) => '&lt;',  q(>) => '&gt;', q(") => '&quot;',
    q(') => '&#39;', q(`) => '&#96;', '\\' => '&#92;',
);
my $AMP = qr/[$ALPHA][$ALNUM]*|\#(?:[$DIGIT]{1,10}|x[$XDIGIT]{2,8})/msx;
my $ANCHOR = qr{[^\P{Graph}\[\]]+(?:[ \t]+[^\P{Graph}\[\]]+)*}msx;
my $LABEL = qr{[^\P{Graph}\[\]]+(?:\s+[^\P{Graph}\[\]]+)*}msx;
my $HRULE = qr/(?:[*]$WS*){3,} | (?:[-]$WS*){3,} | (?:[_]$WS*){3,}/msx;
my $BLANK = qr/$WS* \n/msx;
my $INDENTED = qr/$TAB $WS* \S [^\n]* \n/msx;
my $BLOCKQUOTE = qr{
    $PAD > [^\n]* \n (?:(?:$PAD [^\s>] | $TAB $WS* \S) [^\n]* \n)*
}msx;
my $ULMARK = qr/(?!$HRULE\n)[*+-]/msx;
my $OLMARK = qr/[$DIGIT]+[.]/msx;
my $DDMARK = qr/:/msx;
my $LAZY = qr{
    \S [^\n]* \n
    (?: (?: $PAD (?! $ULMARK $WS | $OLMARK $WS | $DDMARK $WS) | $TAB $WS*)
        \S [^\n]* \n )*
}msx;
my $ITEM = qr/$LAZY (?:$BLANK* (?:$TAB $WS* $LAZY)+ )*/msx;
my $DTITEM = qr/$PAD (?! $DDMARK $WS) \S [^\n]* \n/msx;
my %EMPHASIS_TOKEN = (
    q(*)   => [[1, q(*)]], q(**) => [[2, q(**)]], q(***) => [[3, q(***)]],
    q(_)   => [[4, q(_)]], q(__) => [[5, q(__)]], q(___) => [[6, q(___)]],
    q(*__) => [[1, q(*)],  [5, q(__)]],
    q(**_) => [[2, q(**)], [4, q(_)]],
    q(_**) => [[4, q(_)],  [2, q(**)]],
    q(__*) => [[5, q(__)], [1, q(*)]],
);
my $EMPHASIS_MIDDLE = 0;
my $EMPHASIS_LEFT = 1;
my $EMPHASIS_RIGHT = 2;
my $EMPHASIS_BOTH = 3;
my @EMPHASIS_DFA = (
    [ 0,  1,  2,  3,  4,  5,  6],
    [ 1,  0,  7,  1,  1,  8,  1],   # S0 '*'.S1 '*' S0
    [ 2,  9,  0,  2, 10,  2,  2],   # S0 '**'.S2 '**' S0
    [ 3,  2,  1,  0,  3,  3,  3],   # S0 '***'.S3 '***' S0
    [ 4,  4, 11,  4,  0, 12,  4],   # S0 '_'.S4 '_' S0
    [ 5, 13,  5,  5, 14,  0,  5],   # S0 '__'.S5 '__' S0
    [ 6,  6,  6,  6,  5,  4,  0],   # S0 '___'.S6 '___' S0
    [ 7,  7,  1,  0,  7,  7,  7],   # S0 '*' S1 '**'.S7 '**' S1 '*' S0
    [ 8,  8,  8,  8,  8,  1,  8],   # S0 '*' S1 '__'.S8 '__' S1 '*' S0
    [ 9,  2,  9,  0,  9,  9,  9],   # S0 '**' S2 '*'.S9 '*' S2 '**' S0
    [10, 10, 10, 10,  2, 10, 10],   # S0 '**' S2 '_'.S10 '_' S2 '**' S0
    [11, 11,  4, 11, 11, 11, 11],   # S0 '_' S4 '**'.S11 '**' S4 '_' S0
    [12, 12, 12, 12, 12,  4,  0],   # S0 '_' S4 '__'.S12 '__' S4 '_' S0
    [13,  5, 13, 13, 13, 13, 13],   # S0 '__' S5 '*'.S13 '*' S5 '__' S0
    [14, 14, 14, 14,  5, 14,  0],   # S0 '__' S5 '_'.S14 '_' S5 '__' S0
);

sub new {
    my($class, $init) = @_;
    $init = +{ref $init eq 'HASH' ? %{$init} : ()};
    my $self = bless $init, ref $class || $class;
    return $self;
}

sub middle_word_underscore {
    my($self, @arg) = @_;
    return @arg ? ($self->{'middle_word_underscore'} = $arg[0])
        : $self->{'middle_word_underscore'};
}

sub markdown {
    my($self, $src) = @_ == 1 ? (__PACKAGE__->new, $_[0]) : @_;
    chomp $src; $src = "\n\n$src\n\n"; $src =~ s/^$WS+$//gmsxo;
    my $c = {'reflink' => {}, 'footnote' => {}};
    my $fn = 0;
    my @toplevel = (q());
    while ($src =~ m{\G
        (?: (?<=\n\n)
            (<  (?: ($BLOCKTAG) $HTML5_ATTR [ \t\n]*(?:/>|>.*?</\2[ \t\n]*>)
                |   hr $HTML5_ATTR [ \t\n]* /?>
                |   !-- .*? --> )
                $WS*\n)\n #1 #2
        |   ```([\-_$ALNUM]*)\n(.*?)\n```\n #3 #4
        |   $PAD \[\^($ANCHOR)\][:]((?:$WS+(?:\S[^\n]*)?)?\n
                (?:$BLANK* $INDENTED+)*) #5 #6
        |   $PAD \[($ANCHOR)\][:] $WS+ (?:<(\S+?)>|(\S+)) #7 #8 #9
            (?: (?:$WS+(?:\n$WS*)?|\n$WS*)
                (?:"([^\n]*)"|'([^\n]*)'|[(]($NEST_PAREN)[)]) #10 #11 #12
            )? $WS* \n
        |   ([^\n]*\n) #13
        )
    }gcmsxo) {
        if (defined $1) {
            push @toplevel, "\n$1";
        }
        elsif (defined $4) {
            my $x = _htmlall_escape($4);
            push @toplevel, "\n<pre><code>$x</code></pre>\n";
        }
        elsif (defined $5) {
            my($k, $x) = (_linklabel($5), $6);
            next if exists $c->{'footnote'}{$k};
            $x =~ s/\A\s+//msxo; $x =~ s/^$TAB//gmsxo;
            $c->{'footnote'}{$k} = [++$fn, _htmlall_escape("fn:$k"), $x];
        }
        elsif (defined $7) {
            my $k = _linklabel($7);
            my $uri = defined $8 ? $8 : $9;
            my $title = defined $10 ? $10 : defined $11 ? $11 : $12;
            $c->{'reflink'}{$k} = [$uri, $title];
        }
        elsif (defined $13) {
            if (ref $toplevel[-1]) {
                $toplevel[-1][0] .= $+;
            }
            else {
                push @toplevel, [$+];
            }
        }
    }
    my $dst = q();
    for my $x (@toplevel) {
        $dst .= ! ref $x ? $x : $self->_parse_block($c, q(), $x->[0], q());
    }
    if (keys %{$c->{'footnote'}}) {
        $dst .= "\n<hr />\n";
        $dst .= qq(\n<ol class="footnote">\n);
        for (sort { $a->[0] <=> $b->[0] } values %{$c->{'footnote'}}) {
            my($fn, $id, $x) = @{$_};
            $dst .= $self->_parse_block($c, qq(<li id="$id">), $x, "</li>\n");
        }
        $dst .= "</ol>\n";
    }
    $dst =~ s/\A\s+//msx;
    return $dst;
}

sub _parse_block {
    my($self, $c, $stag, $src, $etag) = @_;
    chomp $src; $src .= "\n"; $src =~ s/^$WS+$//gmsxo;
    my $litag = $stag =~ m/<(?:li|dd)/msx ? 1 : 0;
    my $dst = $stag;
    while ($src =~ m{\G
        (?: () $BLANK+ #1
        |   ($INDENTED+ (?:$BLANK+ $INDENTED+)*) #2
        |   () $PAD $HRULE \n #3
        |   ($BLOCKQUOTE+ (?:$BLANK+ $BLOCKQUOTE+)*) #4
        |   $PAD (\#{1,5})\#* $WS* (.+?) $WS* (?:\#+ $WS*)? \n #5 #6
        |   $PAD $ULMARK $WS+ ($ITEM) #7
        |   $PAD $OLMARK $WS+ ($ITEM) #8
        |   $PAD (\S [^\n]*) \n $PAD (=|-)\10* \n #9 #10
        |   ($DTITEM+) $BLANK* $PAD $DDMARK $WS+ ($ITEM) #11 #12
        |   ($PAD $LAZY) #13
        )
    }gcmsxo) {
        next if defined $1;
        if (defined $13 && ! $litag) {
            my $x = $13;
            if ($src =~ m/\G((?:$WS* \S [^\n]* \n)+)/gcmsxo) {
                $x .= $1;
            }
            chomp $x;
            $dst .= "\n<p>" . $self->_parse_inline($c, $x, 0) . "</p>\n";
        }
        elsif (defined $13) {
            my $x = $13; chomp $x;
            $dst .= $self->_parse_inline($c, $x, 0);
        }
        elsif (defined $10) {
            my $n = $10 eq q(=) ? 1 : 2;
            $dst .= "\n<h$n>" . $self->_parse_inline($c, $9, 0) . "</h$n>\n";
        }
        elsif (defined $6) {
            my $n = length $5;
            $dst .= "\n<h$n>" . $self->_parse_inline($c, $6, 0) . "</h$n>\n";
        }
        elsif (defined $7) {
            my $x = $7; $x =~ s/^$TAB//gmsxo;
            $dst .= "\n<ul>\n" . $self->_parse_block($c, '<li>', $x, "</li>\n");
            while ($src =~ m/\G$BLANK* $PAD $ULMARK $WS+ ($ITEM)/gcmsxo) {
                my $x = $1; $x =~ s/^$TAB//gmsxo;
                $dst .= $self->_parse_block($c, '<li>', $x, "</li>\n");
            }
            $dst .= "</ul>\n";
        }
        elsif (defined $8) {
            my $x = $8; $x =~ s/^$TAB//gmsxo;
            $dst .= "\n<ol>\n" . $self->_parse_block($c, '<li>', $x, "</li>\n");
            while ($src =~ m/\G$BLANK* $PAD $OLMARK $WS+ ($ITEM)/gcmsxo) {
                my $x = $1; $x =~ s/^$TAB//gmsxo;
                $dst .= $self->_parse_block($c, '<li>', $x, "</li>\n");
            }
            $dst .= "</ol>\n";
        }
        elsif (defined $12) {
            my($dt, $dd) = ($11, $12);
            $dst .= "\n<dl>\n";
            while (1) {
                for my $x (split /\n/msxo, $dt) {
                    $dst .= '<dt>' . $self->_parse_inline($c, $x, 0) . "</dt>\n";
                }
                $dd =~ s/^$TAB//gmsxo;
                $dst .= $self->_parse_block($c, '<dd>', $dd, "</dd>\n");
                if ($src =~ m{\G
                    $BLANK* (?:($DTITEM+) $BLANK*)? $PAD $DDMARK $WS+ ($ITEM)
                }gcmsxo) {
                    ($dt, $dd) = (defined $1 ? $1 : q(), $2);
                    next;
                }
                last;
            }
            $dst .= "</dl>\n";
        }
        elsif (defined $4) {
            my $x = $4; $x =~ s/^$PAD>$WS?//gmsxo;
            $dst .= $self->_parse_block($c, "\n<blockquote>", $x, "</blockquote>\n");
        }
        elsif (defined $3) {
            $dst .= "\n<hr />\n";
        }
        elsif (defined $2) {
            my $x = $2; $x =~ s/^$TAB//gmsxo; chomp $x; 
            $dst .= "\n<pre><code>" . _htmlall_escape($x) . "</code></pre>\n";
        }
        $litag = 0;
    }
    return $dst . $etag;
}

sub _parse_inline {
    my($self, $c, $src, $already) = @_;
    my $emphasis = [0, 0, 0];
    my $list = [];
    while ($src =~ m{\G
        (.*?) #1
        (   () \z #2 #3
        |   \\(`+|[ ]+|[\\*_<>{}\[\]()\#+\-.!]) #4
        |   ($HTML5_TAG) #5
        |   <(?:mailto:)?([-.\w+]+\@[-\w]+(?:[.][-\w]+)*[.][$ALPHA]+)> #6
        |   <(\S+)> #7
        |   (`+)$WS*(.*?)$WS*\8 #8 #9
        |   (^|(?<=[ ]))?([*_]+)($|(?=[ ,.;:?!]))? #10 #11 #12
        |   (?<!\\)\[\^($LABEL)(?<!\\)\] #13
        |   ([!]?)(?<!\\)\[($NEST_BRACKET)(?<!\\)\] #14 #15
            (   (?<!\\)[(] \s* (?:<([^>]*?)>|($NEST_PAREN)) #16 #17 #18
                (?:\s* (?:"(.*?)"|'(.*?)'))? \s* (?<!\\)[)]  #19 #20
            |   \s*(?<!\\)\[($LABEL)?(?<!\\)\] #21
            )?
        )
    }gcmsxo) {
        if ($1 ne q()) {
            my $x = _html_escape($1);
            $x =~ s{[ ][ ]\n}{<br />\n}gmsx;
            push @{$list}, $x;
        }
        last if defined $3;
        if (defined $5) {
            push @{$list}, $5;
            next;
        }
        if (defined $6) {
            my $uri = _mail_escape("mailto:$6");
            my $x = _mail_escape($6);
            push @{$list}, qq(<a href="$uri">$x</a>);
            next;
        }
        if (defined $7) {
            my $uri = _uri_escape($7);
            my $x = _html_escape($7);
            push @{$list}, qq(<a href="$uri">$x</a>);
            next;
        }
        if (defined $9) {
            push @{$list}, '<code>' . _htmlall_escape($9) . '</code>';
            next;
        }
        if (defined $11) {
            my $mark = $11;
            my $side = (defined $10 ? $EMPHASIS_LEFT  : 0)
                     + (defined $12 ? $EMPHASIS_RIGHT : 0);
            if ($side != $EMPHASIS_BOTH
                && ! ($self->middle_word_underscore
                    && $side == $EMPHASIS_MIDDLE && $mark =~ m/\A_+\z/msx)
                && exists $EMPHASIS_TOKEN{$mark}
            ) {
                for (@{$EMPHASIS_TOKEN{$mark}}) {
                    $self->_turn_emphasis_dfa($list, $emphasis, $side, @{$_});
                }
                next;
            }
        }
        if (defined $13 && ! $already) {
            my $k = _linklabel($13);
            if (exists $c->{'footnote'}{$k}) {
                my($n, $id) = @{$c->{'footnote'}{$k}}; # id is already escaped
                push @{$list}, qq(<a href="#$id" rel="footnote">$n</a>);
                next;
            }
        }
        if (defined $15 && ($14 || ! $already)) {
            my($img, $x, $uri, $y) = ($14, $15);
            my $suffix = defined $16 ? $16 : q();
            if (defined $17 || defined $18) {
                $uri = defined $17 ? $17 : $18;
                $y = defined $19 ? $19 : $20;
            }
            else {
                my $k = _linklabel(defined $21 ? $21 : $15);
                if (exists $c->{'reflink'}{$k}) {
                    ($uri, $y) = @{$c->{'reflink'}{$k}};
                }
            }
            $uri = defined $uri ? _uri_escape($uri) : $uri;
            my $title = defined $y ? q( title=") . _html_escape($y) . q(") : q();
            if (defined $uri && $img) {
                $x = _html_escape($x);
                push @{$list}, qq(<img src="$uri" alt="$x"$title />);
                next;
            }
            elsif (defined $uri) {
                push @{$list}, qq(<a href="$uri"$title>);
                push @{$list}, $self->_parse_inline($c, $x, 1);
                push @{$list}, q(</a>);
                next;
            }
            else {
                push @{$list}, $img . q([);
                push @{$list}, $self->_parse_inline($c, $x, $already);
                push @{$list}, _html_escape(q(]) . $suffix);
                next;
            }
        }
        push @{$list}, _htmlall_escape(defined $4 ? $4 : $2);
    }
    return join q(), @{$list};
}

sub _turn_emphasis_dfa {
    my($self, $list, $emphasis, $side, $token, $mark) = @_;
    my($state, $match1, $match2) = @{$emphasis};
    my $jump = $EMPHASIS_DFA[$state][$token];
    push @{$list}, $mark;
    return if $state == $jump;
    return if $state < $jump && $side == $EMPHASIS_RIGHT;
    return if $state > $jump && $side == $EMPHASIS_LEFT;
    $emphasis->[0] = $jump;

    if ($state == 0) {
        $emphasis->[1] = $#{$list};
        if ($jump == 3 || $jump == 6) {
            push @{$list}, q();
            $emphasis->[2] = $#{$list};
        }
    }
    elsif ($state == 1 || $state == 4) {
        if ($jump == 0) {
            $list->[$match1] = '<em>';
            $list->[-1] = '</em>';
        }
        else {
            $emphasis->[2] = $#{$list};
        }
    }
    elsif ($state == 2 || $state == 5) {
        if ($jump == 0) {
            $list->[$match1] = '<strong>';
            $list->[-1] = '</strong>';
        }
        else {
            $emphasis->[2] = $#{$list};
        }
    }
    elsif ($state == 7 || $state == 12) {
        if ($jump == 0) {
            $list->[$match2] = '<strong>';
            $list->[-1] = '</strong>';
            $list->[$match1] = '<em>';
            push @{$list}, '</em>';
        }
    }
    elsif ($state == 3 || $state == 6 || $state == 9 || $state == 14) {
        if ($jump == 0) {
            $list->[$match2] = '<em>';
            $list->[-1] = '</em>';
            $list->[$match1] = '<strong>';
            push @{$list}, '</strong>';
        }
    }
    if ($state > 0 && ($jump == 1 || $jump == 4)) {
        $list->[$match2] = '<strong>';
        $list->[-1] = '</strong>';
        if ($state == 3 || $state == 6) {
            my $mark1 = substr $list->[$match1], 0, 1;
            $list->[$match1] = $mark1;
        }
    }
    elsif ($state > 0 && ($jump == 2 || $jump == 5)) {
        $list->[$match2] = '<em>';
        $list->[-1] = '</em>';
        if ($state == 3 || $state == 6) {
            my $mark1 = substr $list->[$match1], 0, 2;
            $list->[$match1] = $mark1;
        }
    }
    return;
}
sub _htmlall_escape {
    my($s) = @_;
    $s =~ s/([&<>"'`\\])/$HTML5_SPECIAL{$1}/egmsx;
    return $s;
}

sub _html_escape {
    my($s) = @_;
    $s =~ s/(&(?:$AMP;)?|[<>"'`\\])/$HTML5_SPECIAL{$1} || $1/egmsx;
    return $s;
}

sub _uri_escape {
    my($s) = @_;
    $s = utf8::is_utf8($s) ? encode_utf8($s) : $s;
    $s =~ s{(%[$XDIGIT]{2})|(&(?:amp;)?)|([^$ALNUM\-_~&*+=/.,;:!?\#])}{
        $1 ? $1 : $2 ? '&amp;' : sprintf '%%%02X', ord $3
    }egmsxo;
    return $s;
}

sub _mail_escape {
    my($s) = @_;
    $s =~ s{([^bdehjkpruwy])}{sprintf '&#%d;', ord $1}egmsxo;
    return $s;
}

# strange case http://bugs.debian.org/459885
sub _linklabel {
    my($id) = @_;
    $id =~ s/\s+/ /gmsx;
    return lc $id;
}

sub _nest_pattern {
    my($r, $n) = @_;
    my $pattern = $r;
    for (1 .. $n) {
        $pattern =~ s/R/$r/msx;
    }
    $pattern =~ s/R//msx;
    return qr{$pattern}msx;
}

1;

__END__

=pod

=head1 NAME

Text::Mkdown - Core Markdown to XHTML text converter.

=head1 VERSION

0.015

=head1 SYNOPSIS

    # OOP style
    use Text::Mkdown;
    
    $xhtml = Text::Mkdown->new->markdown($markdown);
    
    # function style
    use Text::Mkdown qw(markdown);
    
    $xhtml = markdown($markdown);

=head1 DESCRIPTION

=head1 METHODS

=over

=item C<markdown($markdown)>

Converts from a Markdown text string to a XHTML's one.

=item C<new>

Constructs a Markdown processor with initial values for attributes.

    my $m = Text::Markdown->new({'middle_word_underscore' => 1});

=item C<middle_word_underscore>

Boolean attribute accessors. In defaults, it is false.
When its value is true, all of underscores in the middle of words
keep themselves rather than emphasis markers.

=back

=head1 LIMITATIONS

Nesting level of square brackets or parences is up to 6.

Not implement PHP markdown attributes.

    <div markdown="1">**strong**</div>

produces:

    <div markdown="1">**strong**</div>

Not implement PHP extra abbr.

Not implement PHP extra tables.

=head1 DEPENDENCIES

None

=head1 SEE ALSO

L<http://daringfireball.net/projects/markdown/>
L<Text::Markdown>

=head1 AUTHOR

MIZUTANI Tociyuki  C<< <tociyuki\x40gmail.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2013, MIZUTANI Tociyuki C<< <tociyuki@gmail.com> >>.
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
