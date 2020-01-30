# Start at line 10, continue until blank line is found.
{
  if (NR >= 9) {
    if ($1 == "") {exit}
    print $7,$9
  }
}
