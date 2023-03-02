NR==FNR {
    insert = (NR==1 ? "" : insert ORS) $0
    next
}
sub(/^## BEGIN.*/,"") {
  beg = $0 "## BEGIN\n"
  inSub = 1
}
inSub {
  if ( sub(/.*^## END/,"") ) {
    end = "\n## END" $0
    print beg insert end
    inSub = 0
  }
  next
}
{ print }
