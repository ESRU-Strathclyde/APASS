{
  line=FNR
  if (FNR==NR) {
    s[line]=$0
  }
  else {
    s[line]=s[line]" "$2
  }
}

END {
  for (i in s) {
    print s[i]
  }
}
      
    
