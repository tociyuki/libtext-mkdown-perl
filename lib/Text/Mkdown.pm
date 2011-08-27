package Text::Mkdown;
use strict;
use warnings;
use Carp;
use Encode;
use parent qw(Exporter);

use version; our $VERSION = '0.001';
# $Id$

our @EXPORT_OK = qw(markdown);

# character class stay under [:ascii:] before perl version 5.14
my $LOWER = q{a-z};
my $ALPHA = q{A-Za-z};
my $DIGIT = q{0-9};
my $XDIGIT = q{0-9A-Fa-f};
my $ALNUM = q{A-Za-z0-9};

# upto 32 level nested parens or brackets
my $NEST_PAREN = _nest_pattern(q{[^()\\n]*?(?:[(]R[)][^()\\n]*?)*}, 32);
my $NEST_BRACKET = _nest_pattern(q{[^\\[\\]]*(?:\\[R\\][^\\[\\]]*)*}, 32);

# Markdown syntax defines indent as [ ]{4,} or tab.
my $TAB = qr/(?:\t|[ ](?:\t|[ ](?:\t|[ ][ \t])))/msx;
my $PAD = qr/[ ]{0,3}/msx;
# tokenizer in emphasis
my $EM = qr{
    (?: [^<\[(]+?(?:(?:<[^>]*>|\[$NEST_BRACKET\]|[(]$NEST_PAREN[)])+[^<\[(]*?)*
    |   (?:(?:<[^>]*>|\[$NEST_BRACKET\]|[(]$NEST_PAREN[)])+[^<\[(]*?)*
    )
}msx;
# list items
my $HRULE = qr{(?:(?:[*][ ]*){3,}|(?:[-][ ]*){3,}|(?:[_][ ]*){3,}) \n}msx;
my $ULITEM = qr{$PAD (?! $HRULE) [*+-][ \t]+}msx;
my $OLITEM = qr{$PAD [$DIGIT]+[.][ \t]+}msx;
my $ITEMWRAP = qr{(?:(?! $PAD (?:[*+-]|[$DIGIT]+[.])[ \t]+) [^\n]+ \n)*}msx;
my $LINEWRAP = qr{(?:[^\n]+ \n)*}msx;
# html specific patterns
my $BLOCKTAG = qr{
    blockquote|d(?:el|iv|l)|f(?:i(?:eldset|gure)|orm)|h[1-6]|i(?:frame|ns)
|   math|noscript|ol|p(?:re)?|script|table|ul
}msx;
my $HTML5_ATTR = qr{
    (?: [ \t\n]+
        [$ALPHA][-_:$ALNUM]+ [ \t\n]*
        (?:[=] [ \t\n]* (?:"[^"]*"|'[^']*'|`[^`]*`|[^\x00-\x20<>"'`=\x70]+))?
    )*
}msx;
my $HTML5_TAG = qr{
    <
    (?: [$ALPHA][-_:$ALNUM]+ $HTML5_ATTR [ \t\n]* /?>
    |   / [$ALPHA][-_:$ALNUM]+ [ \t\n]* >
    |   !-- .*? -->
    )
}msx;
my %HTML5_SPECIAL = (
    q{&} => q{&amp;}, q{<} => q{&lt;}, q{>} => q{&gt;},
    q{"} => q{&quot;}, q{'} => q{&#39;}, q{`} => q{&#96;}, q{\\} => q{&#92;},
);
my $AMP = qr{(?:[$ALPHA][$ALNUM]*|\#(?:[$DIGIT]{1,5}|x[$XDIGIT]{2,4}))}msx;

sub markdown {
    my($arg0, @arg) = @_;
    if (! ref $arg0) {
        $arg0 ne __PACKAGE__
            or croak q{ReceiverError: could not __PACKAGE__->markdown(...).};
        unshift @arg, $arg0;
        $arg0 = __PACKAGE__->new;
    }
    return $arg0->_toplevel(@arg);
}

sub new {
    my($class) = @_;
    my $self = bless {}, ref $class || $class;
    return $self;
}

sub escape_htmlall {
    my($self, $data) = @_;
    $data =~ s{([&<>"'\`\\])}{ $HTML5_SPECIAL{$1} }egmosx;
    return $data;
}

sub escape_html {
    my($self, $data) = @_;
    $data =~ s{(?:([<>"'\`\\])|\&(?:($AMP);)?)}{
        $1 ? $HTML5_SPECIAL{$1} : $2 ? qq{\&$2;} : q{&amp;}
    }egmosx;
    return $data;
}

sub escape_uri {
    my($self, $uri) = @_;
    if (utf8::is_utf8($uri)) {
        $uri = Encode::encode('utf-8', $uri);
    }
    $uri =~ s{(?:(%([$XDIGIT]{2})?)|(&(?:amp;)?)|([^$ALNUM\-_~&*+=/.!,;:?\#]))}{
        $2 ? $1 : $1 ? '%25' : $3 ? '&amp;' : sprintf '%%%02X', ord $4
    }egmosx;
    return $uri;
}

sub _encode_mailchar {
    my($self, $char) = @_;
    my $r = rand;
    if ($r > 0.9 && $char ne q{@}) {
        return $char;
    }
    else {
        my $fmt = $r > 0.45 ? '&#x%X;' : '&#%d;';
        return sprintf $fmt, ord $char;
    }
}

sub _toplevel {
    my($self, $markdown) = @_;
    $self->{'.links'} = {};
    if (! utf8::is_utf8($markdown)) {
        $markdown = decode('UTF-8', $markdown);
    }
    $markdown =~ s/(?:\r\n?|\n)/\n/gmsx;
    $markdown = "\n\n" . $markdown . "\n\n";
    my @blocks;
    while ($markdown =~ m{\G
        (.*?)
        (?: (\z)
        |   (?<=\n\n)
            (   <  (?: ($BLOCKTAG) $HTML5_ATTR [ \t\n]*>.*?</\4[ \t\n]*>
                |   hr $HTML5_ATTR [ \t\n]* /?>
                |   !-- .*? -->
                )
                [ \t]*\n
            )
            \n
        )
    }gcmsx) {
        my($md, $z, $block_element) = ($1, $2, $3);
        if ($md ne q{}) {
            while ($md =~ s{
                ^$PAD
                \[($NEST_BRACKET)\]: [ \t]+ (?:<(\S+?)>|(\S+))
                (?: (?:[ \t]+(?:\n[ \t]*)?|\n[ \t]*)
                    (?:"([^\n]*)"|'([^\n]*)'|[(]($NEST_PAREN)[)])
                )? [ \t]* \n
            }{}mosx) {
                my($id, $link) = ($1, defined $2 ? $2 : $3);
                my $title = defined $4 ? $4 : defined $5 ? $5 : $6;
                $self->{'.links'}{lc $id} = {'href' => $link, 'title' => $title};
            }
            push @blocks, ['mkd', $md];
        }
        last if defined $z;
        push @blocks, ['html', $block_element];
    }
    my $xhtml = q{};
    for my $e (@blocks) {
        $xhtml .= $e->[0] eq 'html' ? $e->[1] : $self->_block($e->[1]);
    }
    return encode('UTF-8', $xhtml);
}

sub _block {
    my($self, $src, $in_li_flow) = @_;
    my $paragraph = $in_li_flow ? $ITEMWRAP : $LINEWRAP;
    $src =~ s/^[ \t]+$//gmsx;
    $src = "\n\n" . $src . "\n\n";
    my $result = q{};
    while ($src =~ m{\G
        (?: (\n+)
        |   (?<=\n\n)
            (   <  (?: ($BLOCKTAG) $HTML5_ATTR [ \t\n]*>.*?</\3[ \t\n]*>
                |   hr $HTML5_ATTR [ \t\n]* /?>
                |   !-- .*? -->
                )
                [ \t]*\n
            )
            \n
        |   ((?:$TAB [^\n]* \n)+ (?:\n+ (?:$TAB [^\n]* \n)+)*)
        |   $PAD
            (?: (\#{1,6})\#* [ \t]* ([^\n]+?) [ \t]* (?:\#+ [ \t]*)? \n
            |   ([^\n]+?) [ \t]* \n $PAD (=+|-+) [ \t]* \n
            |   () $HRULE
            |   (> [^\n]* \n $LINEWRAP (?:\n* $PAD> [^\n]* \n $LINEWRAP)*)
            |   ([*+-]|[$DIGIT]+[.])[ \t]+ ([^\n]+ \n)
            |   ([^\n]+ \n)
            )
        )
    }gcmsx) {
        next if defined $1;
        if (! $in_li_flow && $result ne q{} && "\n" ne substr $result, -1) {
            $result .= "\n";
        }
        if (defined $13) {
            my $inline = $13;
            if ($src =~ m{\G($paragraph)}gcmsx) {
                $inline .= $1;
            }
            chomp $inline;
            my $t = $self->_inline($inline);
            if ($in_li_flow) {
                $result .= $t;
            }
            else {
                $result .= qq{<p>$t</p>\n};
            }
        }
        elsif (defined $2) {
            $result .= $2;
        }
        elsif (defined $4) {
            my $data = $4;
            $data =~ s/^$TAB//gmsx;
            my $t = $self->escape_htmlall($data);
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
            my $flow = $10;
            $flow =~ s/^[ ]{0,3}>[ \t]?//gmsx;
            my $t = $self->_block($flow);
            $result .= qq{<blockquote>\n$t</blockquote>\n};
        }
        elsif (defined $11) {
            my $inline = $12;
            my $list = length $11 == 1 ? 'ul' : 'ol';
            $result .= qq{<$list>\n};
            my $limark = $list eq 'ul' ? $ULITEM : $OLITEM;
            while (1) {
                if ($src =~ m{\G
                    ($ITEMWRAP (?:\n+ $TAB [^\n]+ \n $ITEMWRAP)*)
                }gcmsx) {
                    $inline .= $1;
                }
                $inline =~ s/^$TAB//gmsx;
                my $t = $self->_block($inline, 'flow');
                $result .= qq{<li>$t</li>\n};
                last if $src !~ m{\G \n* $limark ([^\n]+ \n)}gcmsx;
                $inline = $1; ## no critic qw(CaptureWithoutTest)
            }
            $result .= qq{</$list>\n};
        }
        $in_li_flow = 0;
    }
    return $result;
}

sub _inline {
    my($self, $src, %already) = @_;
    my $result = q{};
    ## no critic qw(EscapedMetacharacters)
    while ($src =~ m{\G
        (.*?)       #1
        (?: (\z)    #2
        |   \\([\\`*_<>\{\}\[\]()\#+\-.!])          #3
        |   (`+)[ \t]*(.+?)[ \t]*(?<!`)\4(?!`)      #4,5
        |   <((?:https?|ftp):[^'">\s]+)>            #6
        |   <(?:mailto:)?([-.\w\+]+\@[-\w]+(?:[.][-\w]+)*[.][$LOWER]+)> #7
        |   ($HTML5_TAG)                            #8
        |   (   (!)?\[($NEST_BRACKET)\]                         #9,10,11
                (?: [(]  [ \t]* (?:<([^>]*?)>|($NEST_PAREN))    #12,13
                    (?:[ \t]+ (?:"(.*?)"|'(.*?)'))?             #14,15
                    [ \t]* [)]
                |   (?:[ ]|\n[ ]*)? \[($NEST_BRACKET)\]         #16
                )
            )
        |   (?:^|(?<![\w*]))
            (?: [*][*]([*_]*(?![\s.,?])$EM(?<![\s*])[*]*)[*][*] #17
            |   [*]([*_]*(?![\s.,?])$EM(?<![\s*])[*]*)[*]       #18
            )
            (?=$|[^\w*])
        |   (?:^|(?<![\w_]))
            (?: [_][_]([_*]*(?![\s.,?])$EM(?<![\s_])[_]*)[_][_] #19
            |   [_]([_*]*(?![\s.,?])$EM(?<![\s_])[_]*)[_]       #20
            )
            (?=$|[^\w_])
        )
    }gcmsx) {
        if ($1 ne q{}) {
            my $text = $self->escape_html($1);
            $text =~ s{[ ]{2,}\n}{<br />\n}gmsx;
            $result .= $text;
        }
        last if defined $2;
        if (defined $3) {
            $result .= $self->escape_htmlall($3);
        }
        elsif (defined $5) {
            $result .= '<code>' . $self->escape_htmlall($5) . '</code>';
        }
        elsif (defined $6) {
            my $href = $self->escape_uri($6);
            my $text = $self->escape_html($6);
            $result .= qq{<a href="$href">$text</a>};
        }
        elsif (defined $7) {
            my $href = 'mailto:' . $7;
            my $text = $7;
            $href =~ s{(.)}{ $self->_encode_mailchar($1) }egmosx;
            $text =~ s{(.)}{ $self->_encode_mailchar($1) }egmosx;
            $result .= qq{<a href="$href">$text</a>};
        }
        elsif (defined $8) {
            $result .= $8;
        }
        elsif (defined $9) {
            my $e = $self->_anchor_or_img({
                'img' => $10,
                'text' => $11,
                'uri' => defined $12 ? $12 : $13,
                'title' => defined $14 ? $14 : $15,
                'id' => $16,
            }, %already);
            $result .= $e || $self->escape_html($9);
        }
        elsif (defined $17 || defined $19) {
            my $t = $self->_inline(defined $17 ? $17 : $19);
            $result .= qq{<strong>$t</strong>};
        }
        elsif (defined $18 || defined $20) {
            my $t = $self->_inline(defined $18 ? $18 : $20);
            $result .= qq{<em>$t</em>};
        }
    }
    return $result;
}

sub _anchor_or_img {
    my($self, $param, %already) = @_;
    return if ! $param->{'img'} && exists $already{'anchor'};
    my($uri, $title) = @{$param}{'uri', 'title'};
    if (! defined $param->{'uri'}) {
        my $id = $param->{'id'};
        $id = defined $id && $id ne q{} ? $id : $param->{'text'};
        $id = lc $id;
        $id =~ s{[ \t]*\n}{ }gmsx;
        if (exists $self->{'.links'}{$id}) {
            ($uri, $title) = @{$self->{'.links'}{$id}}{'href', 'title'};
        }
    }
    return if ! defined $uri;
    $uri = $self->escape_uri($uri);
    $title = ! defined $title ? q{}
        : q{ title="} . $self->escape_html($title) . q{"};
    if ($param->{'img'}) {
        my $alt = $self->escape_html($param->{'text'});
        return qq{<img src="$uri" alt="$alt"$title />};
    }
    else {
        my $text = $self->_inline($param->{'text'}, 'anchor' => 1);
        return qq{<a href="$uri"$title>$text</a>};
    }
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

0.001

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

=item C<escape_htmlall>

=item C<escape_html>

=item C<escape_uri>

=back

=head1 LIMITATIONS

Nesting level of square brackets or parences is up to 32.

Not implement single square bracketed link.

    isnt link [foo].

      [foo]: /example.net/?foo "wiki"

produces:

    <p>isnt link [foo]</p>

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

MIZUTANI Tociyuki  C<< <tociyuki@gmail.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2011, MIZUTANI Tociyuki C<< <tociyuki@gmail.com> >>.
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
