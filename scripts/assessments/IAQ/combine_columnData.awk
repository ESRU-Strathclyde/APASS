BEGIN {
  first_head=1
  first_data=1
  active=0
  line_head=0
  line_data=0
}

{
  if (first_head==1) {
    line_head++
    s[line_head]=$0
  }

  if (active==1) {
    if (substr($0,1,1)=="#") {
      active=0
      first_data=0
      next
    }
    line_data++
    line=line_head+line_data
    if (first_data==1) {
      s[line]=$0
    }
    else {
      s[line]=s[line]gensub($1,"",1)
    }
  }
    
  if ($1=="#Time") {
    active=1
    if (first_head==1) {
      first_head=0
    }
    else {      
      s[line_head]=s[line_head]substr($0,length($1)+1)
    }
    line_data=0
  }
}

END {
  for (i in s) {
    print s[i]
  }
}
      
    
