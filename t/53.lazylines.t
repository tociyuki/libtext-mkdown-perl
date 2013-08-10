use strict;
use warnings;
use Test::More;
use Test::Differences;

plan 'no_plan';

use_ok 'Text::Mkdown';

my $m    = Text::Mkdown->new();
my ($got, $spec);
unified_diff;

#-------------------------------------------------------------------------------
$spec = "list item + list item";
$got = $m->markdown(<<"EOF");
*   item 1 line 1
    item 1 line 2
    item 1 line 3
*   item 2 line 1
    item 2 line 2
    item 2 line 3
EOF
eq_or_diff $got, <<'EOF', $spec;
<ul>
<li>item 1 line 1
item 1 line 2
item 1 line 3</li>
<li>item 2 line 1
item 2 line 2
item 2 line 3</li>
</ul>
EOF

#-------------------------------------------------------------------------------
$spec = "list lazy item + list lazy item";
$got = $m->markdown(<<"EOF");
*   item 1 line 1
item 1 line 2
item 1 line 3
*   item 2 line 1
item 2 line 2
item 2 line 3
EOF
eq_or_diff $got, <<'EOF', $spec;
<ul>
<li>item 1 line 1
item 1 line 2
item 1 line 3</li>
<li>item 2 line 1
item 2 line 2
item 2 line 3</li>
</ul>
EOF

#-------------------------------------------------------------------------------
$spec = "list item + blank + list item";
$got = $m->markdown(<<"EOF");
*   item 1 line 1
    item 1 line 2
    item 1 line 3

*   item 2 line 1
    item 2 line 2
    item 2 line 3
EOF
eq_or_diff $got, <<'EOF', $spec;
<ul>
<li>item 1 line 1
item 1 line 2
item 1 line 3</li>
<li>item 2 line 1
item 2 line 2
item 2 line 3</li>
</ul>
EOF

#-------------------------------------------------------------------------------
$spec = "list lazy item + blank + list lazy item";
$got = $m->markdown(<<"EOF");
*   item 1 line 1
item 1 line 2
item 1 line 3

*   item 2 line 1
item 2 line 2
item 2 line 3
EOF
eq_or_diff $got, <<'EOF', $spec;
<ul>
<li>item 1 line 1
item 1 line 2
item 1 line 3</li>
<li>item 2 line 1
item 2 line 2
item 2 line 3</li>
</ul>
EOF

#-------------------------------------------------------------------------------
$spec = "list lazy item with pre code";
$got = $m->markdown(<<"EOF");
*   quick brown
    fox jumps
    over
    the lazy dog.

        foo
        
        and foo.

*   quick brown
fox jumps
over
the lazy dog.
        foo
        
        and foo.

*   quick brown
fox jumps
over
the lazy dog.

        foo
        
        and foo.
EOF
eq_or_diff $got, <<'EOF', $spec;
<ul>
<li>quick brown
fox jumps
over
the lazy dog.
<pre><code>foo

and foo.
</code></pre>
</li>
<li>quick brown
fox jumps
over
the lazy dog.
<pre><code>foo

and foo.
</code></pre>
</li>
<li>quick brown
fox jumps
over
the lazy dog.
<pre><code>foo

and foo.
</code></pre>
</li>
</ul>
EOF

#-------------------------------------------------------------------------------
$spec = "blockquote paragraph + paragraph";
$got = $m->markdown(<<"EOF");
> paragraph 1 line 1.
> paragraph 1 line 2.
> paragraph 1 line 3.
>
> paragraph 2 line 1.
> paragraph 2 line 2.
> paragraph 2 line 3.
EOF
eq_or_diff $got, <<'EOF', $spec;
<blockquote>
<p>paragraph 1 line 1.
paragraph 1 line 2.
paragraph 1 line 3.</p>
<p>paragraph 2 line 1.
paragraph 2 line 2.
paragraph 2 line 3.</p>
</blockquote>
EOF

#-------------------------------------------------------------------------------
$spec = "blockquote lazy paragraph + quoted blank + lazy paragraph";
$got = $m->markdown(<<"EOF");
> paragraph 1 line 1.
paragraph 1 lazy line 2.
paragraph 1 lazy line 3.
>
> paragraph 2 line 1.
paragraph 2 lazy line 2.
paragraph 2 lazy line 3.
EOF
eq_or_diff $got, <<'EOF', $spec;
<blockquote>
<p>paragraph 1 line 1.
paragraph 1 lazy line 2.
paragraph 1 lazy line 3.</p>
<p>paragraph 2 line 1.
paragraph 2 lazy line 2.
paragraph 2 lazy line 3.</p>
</blockquote>
EOF

#-------------------------------------------------------------------------------
$spec = "blockquote lazy paragraph + blank + lazy paragraph";
$got = $m->markdown(<<"EOF");
> paragraph 1 line 1.
paragraph 1 lazy line 2.
paragraph 1 lazy line 3.

> paragraph 2 line 1.
paragraph 2 lazy line 2.
paragraph 2 lazy line 3.
EOF
eq_or_diff $got, <<'EOF', $spec;
<blockquote>
<p>paragraph 1 line 1.
paragraph 1 lazy line 2.
paragraph 1 lazy line 3.</p>
<p>paragraph 2 line 1.
paragraph 2 lazy line 2.
paragraph 2 lazy line 3.</p>
</blockquote>
EOF

#-------------------------------------------------------------------------------
$spec = "blockquote lazy paragraph + lazy paragraph";
$got = $m->markdown(<<"EOF");
> paragraph 1 line 1.
paragraph 1 lazy line 2.
paragraph 1 lazy line 3.
> paragraph 2 line 1.
paragraph 2 lazy line 2.
paragraph 2 lazy line 3.
EOF
eq_or_diff $got, <<'EOF', $spec;
<blockquote>
<p>paragraph 1 line 1.
paragraph 1 lazy line 2.
paragraph 1 lazy line 3.</p>
<p>paragraph 2 line 1.
paragraph 2 lazy line 2.
paragraph 2 lazy line 3.</p>
</blockquote>
EOF

#-------------------------------------------------------------------------------
$spec = "blockquote paragraph + pre-code";
$got = $m->markdown(<<"EOF");
> quick brown
> fox jumps
> over
> the lazy dog.
> 
>     foo
>     
>     and foo.
EOF
eq_or_diff $got, <<'EOF', $spec;
<blockquote>
<p>quick brown
fox jumps
over
the lazy dog.</p>
<pre><code>foo

and foo.
</code></pre>
</blockquote>
EOF

#-------------------------------------------------------------------------------
$spec = "blockquote paragraph + pre-code";
$got = $m->markdown(<<"EOF");
> quick brown
fox jumps
over
the lazy dog.

>     foo
>     
>     and foo.
EOF
eq_or_diff $got, <<'EOF', $spec;
<blockquote>
<p>quick brown
fox jumps
over
the lazy dog.</p>
<pre><code>foo

and foo.
</code></pre>
</blockquote>
EOF

#-------------------------------------------------------------------------------
$spec = "blockquote paragraph + quoted blank + pre-code";
$got = $m->markdown(<<"EOF");
> quick brown
fox jumps
over
the lazy dog.
>
>     foo
>     
>     and foo.
EOF
eq_or_diff $got, <<'EOF', $spec;
<blockquote>
<p>quick brown
fox jumps
over
the lazy dog.</p>
<pre><code>foo

and foo.
</code></pre>
</blockquote>
EOF

#-------------------------------------------------------------------------------
$spec = "blockquote paragraph + pre-code";
$got = $m->markdown(<<"EOF");
> quick brown
fox jumps
over
the lazy dog.
>     foo
>     
>     and foo.
EOF
eq_or_diff $got, <<'EOF', $spec;
<blockquote>
<p>quick brown
fox jumps
over
the lazy dog.</p>
<pre><code>foo

and foo.
</code></pre>
</blockquote>
EOF

