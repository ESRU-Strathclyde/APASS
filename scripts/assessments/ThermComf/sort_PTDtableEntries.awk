# This script takes entries for the thermal comfort PTD table, and sorts them in descending order of the first column.

BEGIN {
    FS=" & "
    i=0
    active=1
}

{
    if (NF==0) {
        active=0
        j=0
        next
    }
    if (active==1) {
        i++
        lines[i]=$0
        totDisc[i]=substr($3,7,length($3)-2)
    }
    else{
        j++
        lines2[j]=$0
    }
}

END {

    for (i in totDisc) {
        tmpidx[sprintf("%012f", totDisc[i]),sprintf("%07d",1000000-i)] = i
    }
    num = asorti(tmpidx)
    j = 0
    for (i=1; i<=num; i++) {
        split(tmpidx[i], tmp, SUBSEP)
        indices[++j] = 1000000-tmp[2]
    }
    area_cur=""
    for (i=num; i>=1; i--) {
        line=lines[indices[i]]
        split(line,tmp," & ")
        area=tmp[1]
        if (area==area_cur) {sub(area,"",line)}
        else {area_cur=area}
        print line
    }
    print "\nKW_REPLACEME\n\n"    

    # print ""  
    # print "\\end{longtable}"
    # print ""
    # print "\\begin{longtable}{l l p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm}}"
    # print ""
    # print "\\cline{3-8}"
    # print "\\phantom{Area} & \\phantom{Location} & \\multicolumn{6}{c}{\\multirow{2}{12cm}{\\centering{Time of worst violation of the criteria associated with the metrics above\\\\(MM-DD HH:MM)}}} \\\\"
    # print " \\\\"
    # print "\\cline{3-8}"
    # print "\\endfirsthead"
    # print ""
    # print "\\hline"
    # print "\\multicolumn{8}{l}{\\small\\sl continued from previous page} \\\\"
    # print "\\hline"
    # print "\\multirow{3}{*}{Area} & \\multirow{3}{*}{Location} & \\multirow{3}{1.9cm}{\\centering{Operative\\\\temperature}} & \\multirow{3}{1.9cm}{\\centering{Floor\\\\temperature}} & \\multirow{3}{1.8cm}{\\centering{Radiant\\\\asymmetry\\\\(ceiling)}} & \\multirow{3}{1.8cm}{\\centering{Radiant\\\\asymmetry\\\\(wall)}} & \\multirow{3}{1.6cm}{\\centering{Draught}} & \\multirow{3}{1.9cm}{\\centering{Vertical air\\\\temperature\\\\difference}} \\\\"
    # print " \\\\"
    # print " \\\\"
    # print "\\hline"
    # print "\\phantom{Area} & \\phantom{Location} & \\multicolumn{6}{c}{\\multirow{2}{12cm}{\\centering{Time of worst violation of the criteria associated with the metrics above\\\\(MM-DD HH:MM)}}} \\\\"
    # print " \\\\"
    # print "\\cline{3-8}"
    # print "\\endhead"
    # print ""
    # print "\\hline"
    # print "\\multicolumn{8}{r}{\\small\\sl continued on next page} \\\\"
    # print "\\hline"
    # print "\\endfoot"
    # print ""
    # print "\\hline"
    # print "\\endlastfoot"
    # print ""

    area_cur=""
    for (i=num; i>=1; i--) {
        line=lines2[indices[i]]
        split(line,tmp," & ")
        area=tmp[1]
        if (area==area_cur) {sub(area,"",line)}
        else {area_cur=area}
        print line
    }
}