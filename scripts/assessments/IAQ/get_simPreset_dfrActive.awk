BEGIN {
  thisOne=0
  # Default mode = new simulation preset.
  if ( mode == "" ) mode=2
  if ( mode == 1 ) {
    print "error"
    exit
  }
}

{
  if ( mode == 2 ) {
    if ( thisOne == 1 ) {
      if ( $1 == "*scfdr" ) {
        print $2
        exit
      }
    }
    if ( $10 == preset ) {
      thisOne=1
    }
  }
}
