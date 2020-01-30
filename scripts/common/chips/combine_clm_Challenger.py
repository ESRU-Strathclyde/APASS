fIn1=open('Challenger_TMY.clm.a','r')
fIn2=open('Challenger.clm.a','r')
fOut=open('Challenger_comb.clm.a','w')

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
        s=','.join(lsLine2[0:3]+lsLine1[3:5]+[lsLine2[5]]+[lsLine1[6]])
        fOut.write(s+'\n')

fIn1.close()
fIn2.close()
fOut.close()
    
    
