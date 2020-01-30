BEGIN {
  indent=0
}

{
# Skip header line(s).
  if ($1=="***") {next}

# Skip blank lines.
  if ($0=="") {next}

# Read indent.
  s1=match($0,/^ */)
  prev_indent=indent
  indent=RLENGTH

#lala:
#  po=dipsy
  s1=gensub(/^( *)/,"\\1\"","g",$0)
#"lala:
#  "po=dipsy
  s2=gensub(/:/,"\": {","g",s1)
#"lala": {
#  "po=dipsy
  s1=gensub(/=(.*)$/,"\": \"\\1\"","g",s2)
#"lala": {
#  "po": "dipsy",
  if (indent<prev_indent) {
    if (s_prev!="") {print s_prev}
    indent_diff=prev_indent-indent
    for (i=indent_diff;i>2;i=i-2) {
      printf extra_indent
      for (j=indent+i-2;j>0;j--) {
        printf " "
      }
      print "}"
    }
    printf extra_indent
    for (j=indent+i-2;j>0;j--) {
      printf " "
    }
    print "},"
  }
  else if (indent>prev_indent) {
    if (s_prev!="") {print s_prev}
  }
  else {
    if (s_prev!="") {print s_prev ","}
  }
#"lala": {
#  "po": "dipsy",
#}
  s_prev=extra_indent s1
}

END {
  print s_prev
  if (indent!=0) {
    indent_diff=indent-2
    for (i=indent_diff;i>2;i=i-2) {
      printf extra_indent
      for (j=indent+i-2;j>0;j--) {
        printf " "
      }
      print "}"
    }
    printf extra_indent
    for (j=indent+i-2;j>0;j--) {
      printf " "
    }
    print "}"
  }
}
