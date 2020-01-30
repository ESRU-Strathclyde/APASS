BEGIN{
  found=0
}

{
  # Old preset definition.
  if ( $5 == preset ) {
    print 1
    found=1
    exit
  }
  # New preset definition.
  else if ( $10 == preset ) {
    print 2
    found=2
    exit
  }
}

END{
  if ( found == 0 ) {
    print 0
  }
}
