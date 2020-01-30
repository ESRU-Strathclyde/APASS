# Checks results in columns 2+ for nonsense.
# Input arguments vmin and vmax define sensible range of values (default 0-1).
# Any line beginning with a # is ignored.
# If any nonsense is found, output 1.
# If no nonsense is found, output 0.

BEGIN {
  if (vmin=="") {vmin=0.0}
  if (vmax=="") {vmax=1.0}
  badness=0
}

{
	if (substr($1,1,1)=="#") {next}
  for (i=2;i<=NF;i++) {
    if ($i<vmin || $i>vmax) {
      badness=1
      exit
    }
  }
}

END {
  print badness
}