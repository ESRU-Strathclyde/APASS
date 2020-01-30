BEGIN {
  thisOne=0
  # Default mode = new simulation preset.
  if ( mode == "" ) mode=2
}

{
  if ( mode == 1 ) {
    if ( thisOne == 1 ) {
      if ( $1 == "*sflr" ) {
        print $2
        exit
      }
    }
    if ( $5 == preset ) {
      thisOne=1
    }
  }
  else if ( mode == 2 ) {
    if ( thisOne == 1 ) {
      if ( $1 == "*sflr" ) {
        print $2
        exit
      }
    }
    if ( $10 == preset ) {
      thisOne=1
    }
  }
}
