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
    if ($i!="not_occ" && prevVal6!="not_occ") {
        if (sqrt(($i-optimum)^2) > sqrt((prevVal6-optimum)^2)) {
        drift=sqrt(($i-prevVal6)^2);
        if (drift>criteria) {
          recursion--;
          if (!recursion) {
            print(day,$i);
            print(day,prevVal6);
            print(day-6,prevVal6);
            exit;
          }
        }
      }
    }
  }

  # Set previous values to current
  prevVal6=prevVal5;
  prevVal5=prevVal4;
  prevVal4=prevVal3;
  prevVal3=prevVal2;
  prevVal2=prevVal1;
  prevVal1=$i;

  if (first>0) {
    first++;
    if (first>6) {first=0}
  }
}