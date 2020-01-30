BEGIN {
# Default columns = 1
  if (cols=="") {a_cols[1]=1}
  else {split(cols,a_cols,",")}
# Default recursion = 1
  if (recursion=="") {recursion=1}
  active=0;
  for (i in a_cols) {
    toggles[i]=0;
    im_done[i]=0;
    recursions[i]=recursion;
  }
}

{
  s="#";
  if (substr($1,1,1)==s) {next}
  j=1;
  val=0.0;
  for (i=2;i<=NF;i++) {
    j++;

    for (ind in a_cols) {
      if (j==a_cols[ind]) {
        if ($i !~ /^-?[0-9]+\.?[0-9]*$/) {
          if (toggles[ind]) {
            if (recursions[ind]==0) {
              im_done[ind]=1;
            }
            toggles[ind]=0;
          }
        }
        else {
          if (!toggles[ind]) {
            toggles[ind]=1;
            recursions[ind]--;
            if (!recursions[ind]) {active=1}
          }
          if (active) {
            if ($i>val) {val=$i}
          }
        }
        break;
      }
    }
    if ($i == "not" || $i == "no" || $i == "invl") {
      i++;
    }
  }
  done=1;
  for (ind in a_cols) {
    if (!im_done[ind]) {
      done=0;
      break;
    }
  }
  if (done) {exit}
  if (active) {print $1,val}
}
