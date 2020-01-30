BEGIN {
  first=1;
  # default criteria: 1.0
  if (criteria=="") {criteria=1.0}
  # default recursion: 1
  if (recursion=="") {recursion=1}
  # default column: 1
  if (col=="") {col=1}
  i=col;
}

{  
  if (first==0) {
    day=$1;
    optimum=$2;
  }

  # Compare current values with previous.      
  if (first==0) {
    if ($i!="not_occ" && prevVal!="not_occ") {
        if (sqrt(($i-optimum)^2) > sqrt((prevVal-optimum)^2)) {
        drift=sqrt(($i-prevVal)^2);
        if (drift>criteria) {
          recursion--;
          if (!recursion) {
            print(day,$i);
            print(day,prevVal);
            print(day-1,prevVal);
            exit
          }
        }
      }
    }
  }

  # Set previous values to current
  prevVal=$i;

  if (first==1) {
    first=0;
  }
}