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
   
}