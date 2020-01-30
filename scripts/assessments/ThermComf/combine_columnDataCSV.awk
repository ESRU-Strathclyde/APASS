BEGIN {
  first_head=1;
  first_data=1;
  data_count=0;
  active=0;
  line_head=0;
  line_data=0;
  num_cols=0;
}

{

  if ($1=="#Time") {
    active=2;
    data_count++;
    if (first_head==1) {
      line_head++;
      first_head=0;
      num_cols+=NF;
      ls="Time,";
      for (i=2;i<=NF;i++) {
        ls=ls$i",";
      }      
      s["-999."line_head]=ls;
    }
    else {
      num_cols+=NF-1;
      ls="";
      for (i=2;i<=NF;i++) {
        ls=ls$i",";
      }      
      s["-999."line_head]=s["-999."line_head]ls;
    }
    line_data=0;
  }
  else if (first_head==1) {
    line_head++;
    s["-999."line_head]=$0;
  }

  if (active==1) {
    if (substr($0,1,1)=="#") {
      active=0;
      next;
    }
    line_data++;
    line=line_head+line_data;
    if (data_count==1) {
      ind=sprintf("%.4f",$1);
      ls="";
      for (i=1;i<=NF;i++) {
        if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
          ls=ls$i",";
        }
        else {
          ls=ls"-,";
          i++
        }
      }
      s[ind]=ls;
    }
    else {
      ind=sprintf("%.4f",$1);
      ls="";
      for (i=2;i<=NF;i++) {
        if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
          ls=ls$i",";
        }
        else {
          ls=ls"-,";
          i++;
        }
      }
      s[ind]=s[ind]ls;
    }
  }

  if (active>1) {active-=1}
}

END {
  n=asorti(s,s2);
  for (i in s2) {
    ls=s[s2[i]];
    n=split(ls,als,",");
    if (n-1 != num_cols) {
      for (j=n;j<=num_cols;j++) {
        ls=ls"-,";
      }
    }
    print ls;
  }
}
      
    
