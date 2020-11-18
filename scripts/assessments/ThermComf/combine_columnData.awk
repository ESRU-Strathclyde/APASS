BEGIN {
  first_head=1;
  first_data=1;
  active=0;
  line_head=0;
  line_data=0;
}

{
  if (first_head==1) {
    line_head++;
    s["-999."line_head]=$0;
  }

  if (active==1) {
    if (substr($0,1,1)=="#" || $1=="invl") {
      active=0;
      first_data=0;
      next;
    }
    line_data++;
    line=line_head+line_data;
    if (first_data==1) {
      ind=sprintf("%.4f",$1);
      s[ind]=$0;
    }
    else {
      ind=sprintf("%.4f",$1);
      s[ind]=s[ind]substr($0,11);
    }
  }
    
  if ($1=="#Time") {
    active=1;
    if (first_head==1) {
      first_head=0;
    }
    else {      
      s["-999."line_head]=s["-999."line_head]substr($0,length($1)+1);
    }
    line_data=0;
  }
}

END {
  n=asorti(s,s2);
  for (i in s2) {
    print s[s2[i]];
  }
}
      
    
