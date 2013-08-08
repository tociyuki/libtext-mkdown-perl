package Text::Mkdown;
use strict;
use warnings;
use 5.008001;
use Carp;
use Encode;
use parent qw(Exporter);

use version; our $VERSION = '0.009';
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
# Markdown syntax defines indent as [ ]{4} or tab.
my $TAB = qr/(?:\t|[ ](?:\t|[ ](?:\t|[ ][ \t])))/msx;
my $PAD = qr/[ ]{0,3}/msx;
# Instead of specification: letters, numbers, spaces, and punctuation
my $LINK_ANCHOR = qr{[^\P{Graph}\[\]]+(?:[ \t]+[^\P{Graph}\[\]]+)*}msx;
my $LINK_LABEL = qr{[^\P{Graph}\[\]]+(?:\s+[^\P{Graph}\[\]]+)*}msx;
# list items
my $HRULE = qr{(?:(?:[*][ \t]*){3,}|(?:[-][ \t]*){3,}|(?:[_][ \t]*){3,})\n}msx;
my $ULMARK = qr{$PAD (?! $HRULE) [*+-][ \t]+}msx;
my $OLMARK = qr{$PAD [$DIGIT]+[.][ \t]+}msx;
my $ITEM = qr{(?:(?! $PAD (?:[*+-]|[$DIGIT]+[.])[ \t]+) [^\n]+\n)*}msx;
my $LINES = qr{(?:[^\n]+\n)*}msx;
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
my $EMPHASIS = qr{ #'.'
    (?<![*_])
    (?: ([*_])(?![\s.,!?;:*_]|$)(.+?)(?:(?<![\s*_])\1
        #'*' #'<em>2</em>'
        |   (?<![*_])([*][*]|[_][_])(?![\s.,!?;:*_]|$)(.+?)(?<![\s*_])\3
            #'**' #'<em>2<strong>4</strong></em>'
            (?:(?![*_])(.+?)(?<![\s*_]))?\1
            #'<em>2<strong>4</strong>5</em>'
        )
    |   ([*][*]|[_][_])(?![\s.,!?;:*_]|$)(.+?)(?:(?<![\s*_])\6
        #'**' #'<strong>7</strong>'
        |   (?<![*_])([*_])(?![\s.,!?;:*_]|$)(.+?)(?<![\s*_])\8
            #'*' #'<strong>7<em>9</em></strong>'
            (?:(?![*_])(.+?)(?<![\s*_]))?\6
            #'<strong>7<em>9</em>10</strong>'
        )
    |   ([*][*]|[_][_])([*_])(?![\s.,!?;:*_]|$)(.+?)(?<![\s*_])\12
        #'**' #'*' #'<strong><em>13</em></strong>'
        (?:(?![*_])(.+?)(?<![\s*_]))?\11
        #'<strong><em>13</em>14</strong>'
    |   ([*_])([*][*]|[_][_])(?![\s.,!?;:*_]|$)(.+?)(?<![\s*_])\16
        #'*' #'**' #'<em><strong>17</strong></em>'
        (?:(?![*_])(.+?)(?<![\s*_]))?\15
        #'<em><strong>17</strong>18</em>' 
    )
    (?![*_])
}msx;
my @EMPHASIS_TEMPLATE = $EMPHASIS =~ m{\#'(.*?)'}gmosx;

sub new {
    my($class) = @_;
    my $self = bless {}, ref $class || $class;
    return $self;
}

sub markdown {
    my($self, $src) = @_ == 1 ? (__PACKAGE__->new, $_[0]) : @_;
    $self->{'links'} = {};
    $src =~ s/(?:\r\n?|\n)/\n/gmsx;
    chomp $src;
    $src .= "\n";
    while ($src =~ s{
        ^$PAD
        \[($LINK_ANCHOR)\]: [ \t]+ (?:<(\S+?)>|(\S+))
        (?: (?:[ \t]+(?:\n[ \t]*)?|\n[ \t]*)
            (?:"([^\n]*)"|'([^\n]*)'|[(]($NEST_PAREN)[)])
        )? [ \t]* \n
    }{}mosx) {
        my($id, $link) = ($1, defined $2 ? $2 : $3);
        my $title = defined $4 ? $4 : defined $5 ? $5 : $6;
        $self->{'links'}{_id(lc $id)} = [$link, $title];
    }
    return $self->_block($src);
}

# strange case http://bugs.debian.org/459885
sub _id {
    my($id) = @_;
    $id =~ s/\s+/ /gmsx;
    return $id;
}

sub _escape_htmlall {
    my($data) = @_;
    $data =~ s{([&<>"'\`\\])}{ $HTML5_SPECIAL{$1} }egmosx;
    return $data;
}

sub _escape_html {
    my($data) = @_;
    $data =~ s{(?:([<>"'\`\\])|\&(?:($AMP);)?)}{
        $1 ? $HTML5_SPECIAL{$1} : $2 ? qq{\&$2;} : q{&amp;}
    }egmosx;
    return $data;
}

sub _escape_uri {
    my($uri) = @_;
    if (utf8::is_utf8($uri)) {
        $uri = Encode::encode('utf-8', $uri);
    }
    $uri =~ s{(?:(%([$XDIGIT]{2})?)|(&(?:amp;)?)|([^$ALNUM\-_~&*+=/.!,;:?\#]))}{
        $2 ? $1 : $1 ? '%25' : $3 ? '&amp;' : sprintf '%%%02X', ord $4
    }egmosx;
    return $uri;
}

sub _encode_mailchar {
    my($char) = @_;
    my $r = rand;
    if ($r > 0.9 && $char ne q{@}) {
        return $char;
    }
    else {
        my $fmt = $r > 0.45 ? '&#x%X;' : '&#%d;';
        return sprintf $fmt, ord $char;
    }
}

sub _block {
    my($self, $src, $in_flow) = @_;
    $src =~ s/^[ \t]+$//gmsx;
    $src = "\n\n" . $src . "\n\n";
    my $result = q{};
    while ($src =~ m{\G
        (?: ((?:[ \t]*\n)+)
        |   (?<=\n\n)
            (   <  (?: ($BLOCKTAG) $HTML5_ATTR [ \t\n]*(?:/>|>.*?</\3[ \t\n]*>)
                |   hr $HTML5_ATTR [ \t\n]* /?>
                |   !-- .*? -->
                )
                [ \t]*\n
            )
            \n
        |   ((?:$TAB [^\n]+\n)+ (?:\n+ (?:$TAB [^\n]+\n)+)*)
        |   $PAD
            (?: (\#{1,6})\#* [ \t]* ([^\n]+?) (?:[ \t]+(?:\#+[ \t]*)?)? \n
            |   (\S[^\n]*?) [ \t]* \n $PAD (=+|-+) [ \t]* \n
            |   () $HRULE
            |   (> [^\n]*\n $LINES (?:\n* $PAD> [^\n]* \n $LINES)*)
            |   ([*+-]|[$DIGIT]+[.])[ \t]+ (\S[^\n]* \n)
            |   (\S[^\n]* \n)
            )
        )
    }gcmsx) {
        next if defined $1;
        if ($in_flow && $result ne q{} && "\n" ne substr $result, -1) {
            $result .= "\n";
            $in_flow = q();
        }
        if (defined $13) {
            my $inline = $13;
            if ($in_flow) {
                $inline .= $src =~ m{\G($ITEM)}gcmsx ? $1 : q();
            }
            else {
                $inline .= $src =~ m{\G($LINES)}gcmsx ? $1 : q();
            }
            chomp $inline;
            my $t = $self->_inline($inline);
            $result .= $in_flow ? $t : qq{<p>$t</p>\n};
        }
        elsif (defined $2) {
            $result .= $2;
        }
        elsif (defined $4) {
            my $data = $4;
            $data =~ s/^$TAB//gmsx;
            my $t = _escape_htmlall($data);
            $result .= qq{<pre><code>$t</code></pre>\n};
        }
        elsif (defined $5) {
            my $n = length $5;
            my $t = $self->_inline($6);
            $result .= qq{<h$n>$t</h$n>\n};
        }
        elsif (defined $8) {
            my $n = (substr $8, 0, 1) eq q{=} ? 1 : 2;
            my $t = $self->_inline($7);
            $result .= qq{<h$n>$t</h$n>\n};
        }
        elsif (defined $9) {
            $result .= qq{<hr />\n};
        }
        elsif (defined $10) {
            my $data = $10;
            $data =~ s/^$PAD>[ \t]?//gmsx;
            my $t = $self->_block($data);
            $result .= qq{<blockquote>\n$t</blockquote>\n};
        }
        elsif (defined $11) {
            my $data = $12;
            my $list = length $11 == 1 ? 'ul' : 'ol';
            $result .= qq{<$list>\n};
            my $limark = $list eq 'ul' ? $ULMARK : $OLMARK;
            while (1) {
                if ($src =~ m{\G
                    ($ITEM (?:\n+ $TAB [^\n]+ \n $ITEM)*)
                }gcmsx) {
                    $data .= $1;
                }
                $data =~ s/^$TAB//gmsx;
                my $t = $self->_block($data, 'flow');
                $result .= qq{<li>$t</li>\n};
                $data = $src =~ m{\G \n* $limark ([^\n]+ \n)}gcmsx ? $1 : last;
            }
            $result .= qq{</$list>\n};
        }
    }
    return $result;
}

sub _inline {
    my($self, $src) = @_;
    my $c = $self->_iilex({'str' => q(), 'token' => []}, $src);
    my $s = $c->{'str'};
    $s =~ s{$EMPHASIS}{ _emphasis($s, [@-], [@+]) }egmosx;
    $s =~ s{<([$DIGIT]+)>}{$c->{token}[$1]}egmsx;
    return $s;
}

sub _emphasis {
    my($s, $sp, $ep) = @_;
    my $t = $EMPHASIS_TEMPLATE[$#{$sp}];
    $t =~ s{([$DIGIT]+)}{
        substr $s, $sp->[$1], $ep->[$1] - $sp->[$1]
    }egmosx;
    return $t;
}

sub _iilex {
    my($self, $c, $src, %already) = @_;
    my $ref = $self->{'links'};
    ## no critic qw(EscapedMetacharacters)
    while ($src =~ m{\G
        (.*?)       #1:text
        (?: () \z   #2:eos
        |   \\([\\`*_<>{}\[\]()\#+\-.!])    #3:esc
        |   (<!--.*?-->|</?\w[^>]+>)        #4:tag    
        |   (`+)[ \t]*(.*?)[ \t]*\5         #5:code #6:code
        |   ([!]?)\[($NEST_BRACKET)\]       #7:link #8:link
            (   [(] [ \t]* (?:<([^>]*?)>|($NEST_PAREN)) #9:link #10:link #11:link
                (?:[ \t]+ (?:"(.*?)"|'(.*?)'))? [ \t]* [)]  #12:link #13:link
            |   (?:[ \t]|\n[ \t]*)? \[((?:$LINK_LABEL)?)\]     #14:link
            )
        )
    }gcmosx) {
        if ($1 ne q{}) {
            my $text = _escape_html($1);
            $text =~ s{[ ]{2,}\n}{<br />\n}gmsx;
            $c->{str} .= $text;
        }
        last if defined $2;
        if (defined $3) {
            push @{$c->{token}}, _escape_html($3);
            $c->{str} .= q(<) . $#{$c->{token}} . q(>);
            next;
        }
        if (defined $4) {
            $self->_iitag($c, $4);
            next;
        }
        if (defined $5) {
            push @{$c->{token}}, '<code>' . _escape_htmlall($6) . '</code>';
            $c->{str} .= q(<) . $#{$c->{token}} . q(>);
            next;
        }
        if ($7 || ! $already{'link'}) {
            my $r = ! defined $14 ? undef
                : $14 ne q() ? $ref->{_id(lc $14)} : $ref->{_id(lc $8)};
            if ($r) {
                $self->_iilink($c, $7, $8, $r->[0], $r->[1], %already);
                next;
            }
            my $link = defined $10 ? $10 : $11;
            if (defined $link) {
                my $title = defined $12 ? $12 : $13;
                $self->_iilink($c, $7, $8, $link, $title, %already);
                next;
            }
        }
        if (defined $8) {
            my($img, $left, $right) = ($7, $8, $9);
            $c->{str} .= $img . q([);
            $self->_iilex($c, $left, %already);
            $c->{str} .= q(]) . _escape_html($right);
        }
    }
    return $c;
}

sub _iitag {
    my($self, $c, $tag) = @_;
    if ($tag =~ m{\A$HTML5_TAG\z}msx) {
        # do nothing
    }
    elsif ($tag =~ m{
        <(?:mailto:)?([-.\w+]+\@[-\w]+(?:[.][-\w]+)*[.][$LOWER]+)>
    }msx) {
        my $href = 'mailto:' . $1;
        my $text = $1;
        $href =~ s{(.)}{ $self->_encode_mailchar($1) }egmosx;
        $text =~ s{(.)}{ $self->_encode_mailchar($1) }egmosx;
        $tag = qq{<a href="$href">$text</a>};
    }
    elsif ($tag =~ m{\A<(\S+)>\z}msx) {
        my $href = _escape_uri($1);
        my $text = _escape_html($1);
        $tag = qq(<a href="$href">$text</a>);
    }
    else {
        $c->{str} .= _escape_html($tag);
        return;
    }
    push @{$c->{token}}, $tag;
    $c->{str} .= q(<) . $#{$c->{token}} . q(>);
    return;
}

sub _iilink {
    my($self, $c, $img, $text, $link, $title, %already) = @_;
    $link = _escape_uri($link);
    $title = defined $title
        ? q( title=") . _escape_html($title) . q(") : q();
    if ($img) {
        my $alt = _escape_html($text);
        push @{$c->{token}}, qq(<img src="$link" alt="$alt"$title />);
        $c->{str} .= q(<) . $#{$c->{token}} . q(>);
    }
    else {
        push @{$c->{token}}, qq(<a href="$link"$title>);
        $c->{str} .= q(<) . $#{$c->{token}} . q(>);
        $self->_iilex($c, $text, %already, 'link' => 1);
        push @{$c->{token}}, q(</a>);
        $c->{str} .= q(<) . $#{$c->{token}} . q(>);
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

0.009

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

=item C<new>

=back

=head1 LIMITATIONS

Nesting level of square brackets or parences is up to 6.

Not implement single square bracketed link.

    isnt link [foo].
    is link [foo][].

      [foo]: /example.net/?foo "wiki"

produces:

    <p>isnt link [foo].
    is link <a href="/example.net/?foo" title="wiki">foo</a>.</p>

Not implement markdown attributes.

    <div markdown="1">**strong**</div>

produces:

    <div markdown="1">**strong**</div>

=head1 DEPENDENCIES

None

=head1 SEE ALSO

L<http://daringfireball.net/projects/markdown/>
L<Text::Markdown>

=head1 AUTHOR

MIZUTANI Tociyuki  C<< <tociyuki\x40gmail.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012, MIZUTANI Tociyuki C<< <tociyuki@gmail.com> >>.
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
