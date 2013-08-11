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
$spec = "fenced code block";
$got = $m->markdown(<<"EOF");
```
Headings
========

*   unordered list
*   unordered list
    *   nested list
    *   nested list
```
EOF
eq_or_diff $got, <<'EOF', $spec;
<pre><code>Headings
========

*   unordered list
*   unordered list
    *   nested list
    *   nested list</code></pre>
EOF

