package Text::Mkdown;
use strict;
use warnings;
use 5.008001;
use Carp;
use Encode;
use parent qw(Exporter);

our $VERSION = '0.012';
# $Id$

our @EXPORT_OK = qw(markdown);

my $ALNUM = 'A-Za-z0-9';
my $ALPHA = 'A-Za-z';
my $LOWER = 'a-z';
my $DIGIT = '0-9';
my $XDIGIT = '0-9A-Fa-f';

# upto 6 level nested parens or brackets
my $NEST_PAREN = _nest_pattern(q{[^()\\n]*?(?:[(]R[)][^()\\n]*?)*}, 6);
my $NEST_BRACKET = _nest_pattern(q{[^\\[\\]]*(?:\\[R\\][^\\[\\]]*)*}, 6);
# html specific patterns
my $BLOCKTAG = qr{
    blockquote|d(?:el|iv|l)|f(?:i(?:eldset|gure)|orm)|h[1-6]|i(?:frame|ns)
    |math|noscript|ol|p(?:re)?|script|table|ul
}msx;
my $HTML5_NAME = qr/[$ALPHA][-_:$ALNUM]*/msx;
my $HTML5_ATTR = qr{
    (?: [ \t\n]+
        $HTML5_NAME
        (?: [ \t\n]* [=] [ \t\n]*
            (?:"[^"]*"|'[^']*'|`[^`]*`|[^\P{Graph}<>"'`=]+)
        )?
    )*
}msx;
my $HTML5_TAG = qr{
    <   (?: $HTML5_NAME $HTML5_ATTR [ \t\n]* /?>
        |   / $HTML5_NAME [ \t\n]* >
        |   !-- .*? -->
        )
}msx;
my %HTML5_SPECIAL = (
    q{&} => q{&amp;}, q{<} => q{&lt;}, q{>} => q{&gt;},
    q{"} => q{&quot;}, q{'} => q{&#39;}, q{`} => q{&#96;}, q{\\} => q{&#92;},
);
my $AMP = qr/[$ALPHA][$ALNUM]*|\#(?:[$DIGIT]{1,10}|x[$XDIGIT]{2,8})/msx;

sub new {
    my($class, $init) = @_;
    $init = +{ref $init eq 'HASH' ? %{$init} : ()};
    my $self = bless $init, ref $class || $class;
    return $self;
}

sub middle_word_underscore {
    my($self, @arg) = @_;
    @arg and $self->{'middle_word_underscore'} = $arg[0];
    return $self->{'middle_word_underscore'};
}

sub markdown {
    my($self, $src) = @_ == 1 ? (__PACKAGE__->new, $_[0]) : @_;
    my $ctx = {
        'reflink' => {},
        'footnote' => {}, 'footitem' => [],
    };
    my @content = $self->_parse_toplevel($ctx, $src);
    my $footitem = delete $ctx->{'footitem'};
    if (@{$footitem}) {
        push @content, ['hr', {}];
        push @content, ['ol', {'class'=>'footnote'}, @{$footitem}];
    }
    return $self->_fold_parse_inline($ctx, @content);
}

# Markdown syntax defines indent as [ ]{4} or tab.
my $TAB = qr/(?:\t|[ ](?:\t|[ ](?:\t|[ ][ \t])))/msx;
my $PAD = qr/[ ]{0,3}/msx;
# Instead of specification: letters, numbers, spaces, and punctuation
my $LINK_ANCHOR = qr{[^\P{Graph}\[\]]+(?:[ \t]+[^\P{Graph}\[\]]+)*}msx;
my $LINK_LABEL = qr{[^\P{Graph}\[\]]+(?:\s+[^\P{Graph}\[\]]+)*}msx;
# Block patterns
my $HRULE = qr{(?:[*][ \t]*){3,}|(?:[-][ \t]*){3,}|(?:[_][ \t]*){3,}}msx;
my $LAZY = qr{(?!(?:[>\#]|[*+\-:][ \t]|[$DIGIT]+[.][ \t]|$HRULE\n))\S[^\n]*}msx;
my $LAZYINDENTS = qr{
    \S[^\n]*\n (?:$PAD $LAZY\n)*
    (?:\n*(?:$TAB [^\n]*\n(?:$PAD $LAZY\n)*)+)*
}msx;
my $INDENTS = qr/(?:$TAB [ \t]*\S[^\n]*\n)*(?:\n+(?:$TAB [ \t]*\S[^\n]*\n)+)*/msx;
my $BLOCKQUOTE = qr/$PAD >[^\n]*\n(?:$PAD $LAZY\n)*/msx;

my $LEXTOPLEVEL = qr{
    (?: (?<=\n\n)
        (<  (?: ($BLOCKTAG) $HTML5_ATTR [ \t\n]*(?:/>|>.*?</\2[ \t\n]*>)
            |   hr $HTML5_ATTR [ \t\n]* /?>
            |   !-- .*? -->
            )
            [ \t]*\n
        ) #1 #2
        \n
    |   ```([\-_$ALNUM]*)\n(.*?)\n```\n #3 #4
    |   $PAD \[(\^$LINK_ANCHOR)\][:]((?:[ \t]+(?:\S[^\n]*)?)?\n$INDENTS) #5 #6
    |   $PAD \[($LINK_ANCHOR)\][:] [ \t]+ (?:<(\S+?)>|(\S+)) #7 #8 #9
        (?: (?:[ \t]+(?:\n[ \t]*)?|\n[ \t]*)
            (?:"([^\n]*)"|'([^\n]*)'|[(]($NEST_PAREN)[)])   #10 #11 #12
        )? [ \t]* \n
    )
}msx;

my $LEXBLOCK = qr{
    (?: () \n+   #1
    |   ($TAB [^\n]*\n$INDENTS)       #2
    |   ($BLOCKQUOTE+(?:\n+$BLOCKQUOTE+)*)  #3
    |   () $PAD $HRULE\n         #4
    |   $PAD [*+\-][ \t]+ ($LAZYINDENTS)        #5
    |   $PAD [$DIGIT]+[.][ \t]+ ($LAZYINDENTS)  #6
    |   $PAD (\#{1,6})\#*[ \t]*(\S[^\n]*?)\s*(?:\#+\s*)?\n     #7 #8
    |   $PAD (\S[^\n]*)\n$PAD (=|-)\10*\n       #9 #10
    |   ((?:$PAD [^\s:][^\n]*\n)+)
        (?:\n*$PAD :[ \t]+($LAZYINDENTS))? #11 #12
    )
}msx;

my $LEXLISTITEM = qr{
    (?: () \n+  #1
    |   ($TAB [^\n]*\n$INDENTS)       #2
    |   ($BLOCKQUOTE+(?:\n+$BLOCKQUOTE+)*) #3
    |   () $PAD $HRULE\n         #4
    |   $PAD [*+\-][ \t]+ ($LAZYINDENTS)        #5
    |   $PAD [$DIGIT]+[.][ \t]+ ($LAZYINDENTS)  #6
    |   $PAD (\#{1,6})\#*[ \t]*(\S[^\n]*?)\s*(?:\#+\s*)?\n     #7 #8
    |   $PAD (\S[^\n]*)\n$PAD (=|-)\10*\n       #9 #10
    |   ((?:$PAD $LAZY\n)+)
        (?:\n*$PAD :[ \t]+($LAZYINDENTS))? #11 #12
    )
}msx;

my $LEXUL = qr{\n*$PAD (?!(?:$HRULE\n))[*+\-][ \t]+($LAZYINDENTS)}msx;
my $LEXOL = qr{\n*$PAD [$DIGIT]+[.][ \t]+($LAZYINDENTS)}msx;
my $LEXDL = qr{
    \n*
    (?: ((?:$PAD $LAZY\n)+)\n* )?
    $PAD :[ \t]+($LAZYINDENTS)
}msx;

sub _parse_toplevel {
    my($self, $ctx, $src) = @_;
    $src =~ s/(?:\r\n?|\n)/\n/gmsx;
    $src =~ s/^[ \t]+$//gmsx;
    chomp $src;
    $src = "\n\n$src\n\n";
    my @list;
    while (1) {
        if ($src =~ m/\G$LEXTOPLEVEL/gcmsxo) {
            if (defined $1) {
                push @list, ['PARSED', $1];
            }
            elsif (defined $3) {
                my($filetype, $s) = ($3, $4);
                push @list, ['pre', {}, ['CODE', $filetype, $s]];
            }
            elsif (defined $5) {
                my $linklabel = _linklabel($5);
                my $s = $6;
                next if exists $ctx->{'footnote'}{$linklabel};
                my $n = 1 + @{$ctx->{'footitem'}};
                my $id = _htmlall_escape('fn:' . (substr $linklabel, 1));
                $ctx->{'footnote'}{$linklabel} = {'href' => q(#).$id, 'n' => $n};
                $s =~ s/\A\s+//msx;
                push @{$ctx->{'footitem'}},
                    ['li', {'id' => $id}, $self->_parse_listitem($ctx, $s)];
            }
            elsif (defined $7) {
                my $linklabel = _linklabel($7);
                my $uri = defined $8 ? $8 : $9;
                my $title = defined $10 ? $10 : defined $11 ? $11 : $12;
                $ctx->{'reflink'}{$linklabel} = [$uri, $title];
            }
        }
        elsif (! _parse_block($self, $ctx, \$src, $LEXBLOCK, \@list)) {
            last;
        }
    }
    return @list;
}

sub _parse_blockseq {
    my($self, $ctx, $src) = @_;
    chomp $src;
    $src = "$src\n\n";
    my @list;
    while (_parse_block($self, $ctx, \$src, $LEXBLOCK, \@list)) {
        # do nothing.
    }
    return @list;
}

sub _parse_listitem {
    my($self, $ctx, $src0) = @_;
    $src0 = q(    ) . $src0;
    my $lazy = q();
    my $src = q();
    while ($src0 =~ m/\G(?:($PAD\S[^\n]*\n)|(\n)|$TAB([^\n]*\n))/gcmsx) {
        my $n = $#-;
        if ($lazy && $n == 3) {
            $src .= "\n";
        }
        $src .= $+;
        $lazy = $n == 1;
    }
    chomp $src;
    $src = "$src\n\n";
    my @list;
    while (_parse_block($self, $ctx, \$src, $LEXLISTITEM, \@list)) {
        # do nothing.
    }
    my($first, @last) = @list;
    if ($first->[0] eq 'p') {
        splice @{$first}, 0, 2;
        if (@last) {
            push @{$first}, ['PARSED', "\n"];
        }
    }
    unshift @last, @{$first};
    return @last;
}

sub _parse_block {
    my($self, $ctx, $refsrc, $pattern, $list) = @_;
    if (${$refsrc} =~ m/\G$pattern/gcmsx) {
        return 1 if defined $1;
        if (defined $11 && ! defined $12) {
            my $s = $11;
            chomp $s;
            push @{$list}, ['p', {}, ['INLINE', $s]];
        }
        elsif (defined $12) {
            my($dt, $dd) = ($11, $12);
            push @{$list}, ['dl', {}];
            while ($dt =~ m/^$PAD (\S[^\n]*)\n/gmsx) {
                push @{$list->[-1]}, ['dt', {}, ['INLINE', $1]];
            }
            push @{$list->[-1]}, ['dd', {}, $self->_parse_listitem($ctx, $dd)];
            while (${$refsrc} =~ m/\G$LEXDL/gcmsxo) {
                my($dt, $dd) = ($1, $2);
                if (defined $dt) {
                    while ($dt =~ m/^$PAD (\S[^\n]*)\n/gmsx) {
                        push @{$list->[-1]}, ['dt', {}, ['INLINE', $1]];
                    }
                }
                push @{$list->[-1]}, ['dd', {}, $self->_parse_listitem($ctx, $dd)];
            }
        }
        elsif (defined $9) {
            my $n = $10 eq q(=) ? 1 : 2;
            push @{$list}, ["h$n", {}, ['INLINE', $9]];
        }
        elsif (defined $7) {
            my $n = length $7;
            push @{$list}, ["h$n", {}, ['INLINE', $8]];
        }
        elsif (defined $6) {
            push @{$list}, ['ol', {}, ['li', {}, $self->_parse_listitem($ctx, $6)]];
            while (${$refsrc} =~ m/\G$LEXOL/gcmsxo) {
                push @{$list->[-1]}, ['li', {}, $self->_parse_listitem($ctx, $1)];
            }
        }
        elsif (defined $5) {
            push @{$list}, ['ul', {}, ['li', {}, $self->_parse_listitem($ctx, $5)]];
            while (${$refsrc} =~ m/\G$LEXUL/gcmsxo) {
                push @{$list->[-1]}, ['li', {}, $self->_parse_listitem($ctx, $1)];
            }
        }
        elsif (defined $4) {
            push @{$list}, ['hr', {}];
        }
        elsif (defined $3) {
            my $s = $3;
            my $t = q();
            my $lazy = q();
            while ($s =~ m{\G
                (?:$PAD[>][ ]*(\n)|$PAD[>][ ]?([^\n]*\n)|[ ]*(\n)|$PAD(\S[^\n]*\n))
            }gcmsx) {
                my $n = $#-;
                if ($lazy && $n == 2) {
                    $t .= "\n";
                }
                $t .= $+;
                $lazy = $n == 4;
            }
            push @{$list}, ['blockquote', {}, $self->_parse_blockseq($ctx, $t)];
        }
        elsif (defined $2) {
            my $s = $2;
            $s =~ s/^$TAB//gmsxo;
            push @{$list}, ['pre', {}, ['code', {}, ['PARSED', _htmlall_escape($s)]]];
        }
        return 1;
    }
    return;
}

# strange case http://bugs.debian.org/459885
sub _linklabel {
    my($id) = @_;
    $id =~ s/\s+/ /gmsx;
    return lc $id;
}

sub _htmlall_escape {
    my($s) = @_;
    $s =~ s{([&<>"'\`\\])}{ $HTML5_SPECIAL{$1} }egmsxo;
    return $s;
}

sub _html_escape {
    my($s) = @_;
    $s =~ s{([<>"'\`\\]|\&(?:$AMP;)?)}{ $HTML5_SPECIAL{$1} || $1 }egmsxo;
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

my %STAGNL = map { $_ => "\n" } qw(ul ol dl hr blockquote);
my %ETAGNL = map { $_ => "\n" }
    qw(p h1 h2 h3 h4 h5 h6 ul ol dl dt dd li blockquote pre);
my %EMPTYELEMENT = ('hr' => 1, 'img' => 1);
my %HREFATTR = map { $_ => 1} qw(href src);

sub _fold_parse_inline {
    my($self, $ctx, @content) = @_;
    my $t = q();
    while (@content) {
        my $x = shift @content;
        my($f, @arg) = @{$x};
        if ($f eq 'INLINE') {
            $t .= $self->_parse_inline($ctx, $arg[0], 0);
        }
        elsif ($f eq 'PARSED') {
            $t .= join q(), @arg;
        }
        elsif ($f eq 'CODE') {
            my($filetype, $source) = @arg;
            unshift @content, ['code', {}, ['PARSED', _htmlall_escape($source)]];
        }
        else {
            my($h, @child) = @arg;
            my($stag, $etag) = (qq(<$f), qq(</$f>));
            for my $k (qw(id class href src rel rev alt title)) {
                next if ! defined $h->{$k};
                my $v = exists $HREFATTR{$k} ? _uri_escape($h->{$k})
                      : _html_escape($h->{$k});
                $stag .= qq( $k="$v");
            }
            if (exists $EMPTYELEMENT{$f}) {
                $t .= $stag . q( />) . ($STAGNL{$f} || q());
            }
            else {
                $stag .= q(>);
                $stag .= $STAGNL{$f} || q();
                $etag .= $ETAGNL{$f} || q();
                unshift @content, ['PARSED', $stag], @child, ['PARSED', $etag];
            }
        }
    }
    return $t;
}

my $LEXINLINE = qr{
    (.*?)       #1
    (?: () \z   #2
    |   \\(`+|[ ]+|[\\*_<>{}\[\]()\#+\-.!])     #3
    |   (<!--.*?-->|</?\w[^>]+>)                #4
    |   (`+)[ \t]*(.*?)[ \t]*\5                 #5 #6
    |   (^|(?<=[ ]))?([*_]+)($|(?=[ ,.;:?!]))?    #7 #8 #9
    |   ([!]?)\[($NEST_BRACKET)(?<!\\)\]               #10 #11
        (   (?<!\\)[(] \s* (?:<([^>]*?)>|($NEST_PAREN))    #12 #13 #14
            (?:\s* (?:"(.*?)"|'(.*?)'))? \s* (?<!\\)[)]    #15 #16
        |   \s*\[($LINK_LABEL)?(?<!\\)\]               #17
        )?
    )
}msx;
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

sub _parse_inline {
    my($self, $ctx, $src, $already) = @_;
    my $links = $ctx->{'reflink'};
    my $emphasis = [0, 0, 0];
    my $list = [];
    while ($src =~ m/\G$LEXINLINE/gcmsxo) {
        if ($1 ne q()) {
            my $s = _html_escape($1);
            $s =~ s{[ ][ ]\n}{<br />\n}gmsx;
            push @{$list}, $s;
        }
        last if defined $2;
        if (defined $3) {
            push @{$list}, _htmlall_escape($3);
        }
        elsif (defined $4) {
            push @{$list}, $self->_parse_angled($4);
        }
        elsif (defined $6) {
            push @{$list}, '<code>'._htmlall_escape($6).'</code>';
        }
        elsif (defined $8) {
            my $mark = $8;
            my $side = (defined $7 ? $EMPHASIS_LEFT  : 0)
                     + (defined $9 ? $EMPHASIS_RIGHT : 0);
            if ($side == $EMPHASIS_BOTH
                || ($self->{'middle_word_underscore'}
                    && $side == $EMPHASIS_MIDDLE && $mark =~ m/\A_+\z/msx)
                || ! exists $EMPHASIS_TOKEN{$mark}) {
                push @{$list}, _htmlall_escape($mark);
            }
            else {
                for (@{$EMPHASIS_TOKEN{$mark}}) {
                    $self->_turn_emphasis_dfa($list, $emphasis, $side, @{$_});
                }
            }
        }
        elsif (defined $11) {
            my $img = $10;
            my $text = $11;
            my $suffix = $12 || q();
            my $uri = undef;
            my $rel = q();
            my $title = undef;
            if (defined $13 || defined $14) {
                $uri = defined $13 ? $13 : $14;
                $title = defined $15 ? $15 : $16;
            }
            elsif (! $img && exists $ctx->{'footnote'}{$text}) {
                my $fn = $ctx->{'footnote'}{$text};
                $uri = $fn->{'href'};
                $rel = q( rel="footnote");
                $text = $fn->{'n'};
            }
            else {
                my $linklabel = _linklabel(defined $17 ? $17 : $text);
                my $a = $links->{$linklabel} || $links->{$text} || [];
                ($uri, $title) = @{$a};
            }
            if (defined $title) {
                my $t = _html_escape($title);
                $title = qq( title="$t");
            }
            else {
                $title = q();
            }
            my $s = q();
            if (! $img && defined $uri && ! $already) {
                $uri = _uri_escape($uri);
                $s .= qq(<a href="$uri"$rel$title>);
                $s .= $self->_parse_inline($ctx, $text, 1);
                $s .= q(</a>);
            }
            elsif ($img && defined $uri) {
                $uri = _uri_escape($uri);
                $text = _html_escape($text);
                $s .= qq(<img src="$uri" alt="$text"$title />);
            }
            else {
                $s .= $img . q([);
                $s .= $self->_parse_inline($ctx, $text, $already);
                $s .= q(]) . $suffix;
            }
            push @{$list}, $s;
        }
    }
    return join q(), @{$list};
}

sub _parse_angled {
    my($self, $src) = @_;
    if ($src =~ m{\A$HTML5_TAG\z}msx) {
        # do nothing
    }
    elsif ($src =~ m{
        <(?:mailto:)?([-.\w+]+\@[-\w]+(?:[.][-\w]+)*[.][$LOWER]+)>
    }msx) {
        my $href = _mail_escape('mailto:' . $1);
        my $text = _mail_escape($1);
        $src = qq{<a href="$href">$text</a>};
    }
    elsif ($src =~ m{\A<(\S+)>\z}msx) {
        my $href = _uri_escape($1);
        my $text = _html_escape($1);
        $src = qq(<a href="$href">$text</a>);
    }
    else {
        $src = _escape_html($src);
    }
    return $src;
}

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

0.012

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
