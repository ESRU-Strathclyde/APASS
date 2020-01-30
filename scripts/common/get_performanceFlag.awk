# BEGIN {
#   FS="\""
# }

# {
#   if ($2=="building compliance") print $4
# }

{
	print $1
}
