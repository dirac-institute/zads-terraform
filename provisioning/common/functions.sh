#
# Utils to make configuration easier
#

# Copy a file, while expanding certain variables
# cp_with_subst <source> <dest> [variables]
cp_with_subst()
{
	cp "$1" "$2"
	_DEST="$2"
	shift 2
	for VAR in "$@"; do
		sed -i "s|\$$VAR|${!VAR}|g" "$_DEST"
	done
}

# Override yum to automatically say 'yes' and be less verbose
yum()
{
	/usr/bin/yum -y -d1 "$@"
}
