BEGIN {
  first=1;
  # default criteria: 1.0
  if (criteria=="") {criteria=1.0}
  ORS=" ";
}

{
  if (first==0) {
    optimum=$2;
  }

	for (i=3;i<=NF;i++) {

    # Compare current values with previous.      
    if (first==0) {
      if ($i!="not_occ" && prevVals6[i]!="not_occ") {
        if (sqrt(($i-optimum)^2) > sqrt((prevVals6[i]-optimum)^2)) {
          drift=sqrt(($i-prevVals6[i])^2);
          if (drift>criteria) {
            print(drift-criteria);
          }
          else {
            print("x");
          }
        }
        else {
          print("x");
        }
      }
      else {
        print("-");
      }
    }

    # Set previous values to current
    prevVals6[i]=prevVals5[i];
    prevVals5[i]=prevVals4[i];
    prevVals4[i]=prevVals3[i];
    prevVals3[i]=prevVals2[i];
    prevVals2[i]=prevVals1[i];
    prevVals1[i]=$i;
  }

  if (first>0) {
    first++;
    if (first>6) {first=0}
  }
  else {
    print("\n");
  }
}