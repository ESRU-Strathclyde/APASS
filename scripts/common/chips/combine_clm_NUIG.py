fIn1=open('NUIG_TMY.clm.a','r')
fIn2=open('NUIG.clm.a','r')
fOut=open('NUIG_comb.clm.a','w')

i=0
for sLine1,sLine2 in zip(fIn1,fIn2):
    i+=1
    if i==11:
        lsLine1=sLine1.strip().split(',')
        lsLine2=sLine2.strip().split(',')
        s=','.join([lsLine2[0]]+lsLine1[1:])
        fOut.write(s+'\n')
    elif i<14: 
        fOut.write(sLine1)
    elif sLine1[0]=='*' and sLine2[0]=='*':
        fOut.write(sLine1)
    else:
        lsLine1=sLine1.strip().split(',')
        lsLine2=sLine2.strip().split(',')
        s=','.join([lsLine2[0]]+[lsLine1[1]]+[lsLine1[2]]+[lsLine2[3]]+[lsLine1[4]]+[lsLine2[5]]+[lsLine1[6]])
        fOut.write(s+'\n')

fIn1.close()
fIn2.close()
fOut.close()
    
    
