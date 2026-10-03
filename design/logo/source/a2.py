import math,random
W=1024
INK='#1C1D21'; CANVAS='#ECECEC'; TRAY='#FFFFFF'; DTRAY='#24262A'
GREEN='#3EC58F'; BLUE='#5B78EE'; ORANGE='#F2814A'; PURPLE='#D158D6'
PLANE='M0-50C6-50 8-42 8-34L8-12 48 10 48 20 8 8 8 30 20 40 20 48 0 42-20 48-20 40-8 30-8 8-48 20-48 10-8-12-8-34C-8-42-6-50 0-50Z'
uid=[0]
def nid(p): uid[0]+=1; return f'{p}{uid[0]}'
def dashes(x1,y1,x2,y2,col,w=12,d=30,g=22,op=1):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="{w}" stroke-linecap="round" stroke-dasharray="{d} {g}" opacity="{op}"/>'
def plane(x,y,rot,s,col): return f'<path transform="translate({x} {y}) rotate({rot}) scale({s})" d="{PLANE}" fill="{col}"/>'
def arc(x,y,w,h,col): return f'<path d="M{x} {y} q {w/2} {-h} {w} 0" fill="none" stroke="{col}" stroke-width="12" stroke-linecap="round" stroke-dasharray="4 26"/>'

def joined(cx,cy,w,h,ang,cols,bg,r=72,n=44,stub=None,stubcol=None,seam='#fff',gap=0,curve=False):
    """Bitişik biletler: len(cols) panel, aralarında yırtık çizgi; birleşim yerlerinde üst-alt yarım ay."""
    k=len(cols); pw=(w-gap*(k-1))/k; x0=cx-w/2; y0=cy-h/2
    cid=nid('c'); s=f'<g transform="rotate({ang} {cx} {cy})">'
    if gap==0:
        s+=f'<clipPath id="{cid}"><rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="{r}"/></clipPath><g clip-path="url(#{cid})">'
        if curve and k==2:
            sx=x0+pw
            s+=f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="{cols[0]}"/>'
            s+=f'<path d="M{sx} {y0} L{sx} {y0+n+26} C {sx-60} {y0+h*0.35}, {sx+60} {y0+h*0.65}, {sx} {y0+h-n-26} L{sx} {y0+h} L{x0+w} {y0+h} L{x0+w} {y0} Z" fill="{cols[1]}"/>'
        else:
            for i,c in enumerate(cols): s+=f'<rect x="{x0+i*pw}" y="{y0}" width="{pw+1}" height="{h}" fill="{c}"/>'
        if stub: s+=f'<rect x="{x0}" y="{y0+h*stub}" width="{w}" height="{h*(1-stub)}" fill="{stubcol or "#000"}" {"" if stubcol else "opacity=\"0.16\""}/>'
        s+='</g>'
        for i in range(1,k):
            sx=x0+i*pw
            s+=f'<circle cx="{sx}" cy="{y0}" r="{n}" fill="{bg}"/><circle cx="{sx}" cy="{y0+h}" r="{n}" fill="{bg}"/>'
            if curve:
                s+=f'<path d="M{sx} {y0+n+26} C {sx-60} {y0+h*0.35}, {sx+60} {y0+h*0.65}, {sx} {y0+h-n-26}" fill="none" stroke="{seam}" stroke-width="12" stroke-linecap="round" stroke-dasharray="30 22"/>'
            else: s+=dashes(sx,y0+n+26,sx,y0+h-n-26,seam)
    else:
        for i,c in enumerate(cols):
            px=x0+i*(pw+gap); pid=nid('p')
            rl= n if i>0 else r; rr= n if i<k-1 else r
            s+=f'<clipPath id="{pid}"><rect x="{px}" y="{y0}" width="{pw}" height="{h}" rx="{min(rl,rr)}"/></clipPath><g clip-path="url(#{pid})"><rect x="{px}" y="{y0}" width="{pw}" height="{h}" fill="{c}"/>'
            if stub: s+=f'<rect x="{px}" y="{y0+h*stub}" width="{pw}" height="{h*(1-stub)}" fill="#000" opacity="0.16"/>'
            s+='</g>'
            if i>0: s+=f'<circle cx="{px}" cy="{y0}" r="{n}" fill="{bg}"/><circle cx="{px}" cy="{y0+h}" r="{n}" fill="{bg}"/>'
            if i<k-1: s+=f'<circle cx="{px+pw}" cy="{y0}" r="{n}" fill="{bg}"/><circle cx="{px+pw}" cy="{y0+h}" r="{n}" fill="{bg}"/>'
    return s,x0,y0,pw

def svg(bg,body): return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" viewBox="0 0 {W} {W}"><rect width="{W}" height="{W}" fill="{bg}"/>{body}</svg>'
out={}
# A1 · Klasik: mavi + turuncu (ulaşım + yemek), uçuş yayı
t,x0,y0,pw=joined(512,512,620,450,-9,[ORANGE,BLUE],INK,stub=0.64)
out['A1']=svg(INK,t+arc(x0+pw+70,y0+200,170,90,'#fff')+plane(x0+pw+262,y0+186,80,1.15,'#fff')+'</g>')
# A2 · Dört kategori: dört bitişik koçan = uygulamanın dört rengi
t,x0,y0,pw=joined(512,512,700,440,-8,[GREEN,BLUE,ORANGE,PURPLE],INK,n=34,stub=0.64)
out['A2']=svg(INK,t+plane(x0+pw*1.5,y0+150,80,0.9,'#fff')+'</g>')
# A3 · Açık tema: canvas zemin, kapak + koyu koçan (uygulamadaki kart gibi)
t,x0,y0,pw=joined(512,512,620,470,-9,[GREEN,BLUE],CANVAS,stub=0.62,stubcol=DTRAY)
y_s=y0+470*0.62
t+=dashes(x0+60,y_s,x0+620-60,y_s,'#fff',10,24,18,0.9)
t+=f'<rect x="{x0+60}" y="{y_s+56}" width="170" height="28" rx="14" fill="#fff" opacity="0.9"/><rect x="{x0+60}" y="{y_s+106}" width="110" height="22" rx="11" fill="#fff" opacity="0.45"/>'
t+=f'<rect x="{x0+620-150}" y="{y_s+52}" width="88" height="88" rx="12" fill="#fff"/><rect x="{x0+620-132}" y="{y_s+70}" width="22" height="22" fill="{DTRAY}"/><rect x="{x0+620-98}" y="{y_s+104}" width="18" height="18" fill="{DTRAY}"/>'
out['A3']=svg(CANVAS,t+plane(x0+pw*1.5,y0+130,80,1.0,'#fff')+'</g>')
# A4 · Birleşme anı: iki koçan aralıklı, birleşmek üzere (kart animasyonu)
t,x0,y0,pw=joined(512,512,640,430,-9,[ORANGE,BLUE],INK,stub=0.64,gap=44)
mid=x0+pw+22
t+=''.join(f'<line x1="{mid-90-i*0}" y1="{y0+140+i*70}" x2="{mid-60}" y2="{y0+140+i*70}" stroke="#fff" stroke-width="10" stroke-linecap="round" opacity="0.0"/>' for i in range(3))
t+=f'<path d="M{mid-14} {y0+150} l 14 0 M{mid} {y0+150} l 14 0" stroke="#fff" stroke-width="0"/>'
t+=f'<g fill="none" stroke="#fff" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"><path d="M{mid-110} {y0+215} l 34 34 -34 34"/><path d="M{mid+110} {y0+215} l -34 34 34 34"/></g>'
out['A4']=svg(INK,t+plane(x0+pw*1.5+44,y0+120,80,0.9,'#fff')+'</g>')
# A5 · S yırtık çizgi: birleşim yeri hafif "S" çiziyor (isimle bağ)
t,x0,y0,pw=joined(512,512,620,460,-9,[BLUE,ORANGE],INK,stub=None,curve=True)
out['A5']=svg(INK,t+'</g>')
# A6 · Mavi zemin + beyaz/turuncu koçan + birleşim yerinde küçük damga
t,x0,y0,pw=joined(512,512,620,450,-9,[TRAY,ORANGE],BLUE,stub=0.64)
sx=x0+pw; sy=y0+150
st=f'<g transform="rotate(-16 {sx} {sy})"><circle cx="{sx}" cy="{sy}" r="92" fill="none" stroke="#C2343F" stroke-width="12"/><circle cx="{sx}" cy="{sy}" r="70" fill="none" stroke="#C2343F" stroke-width="5"/>{plane(sx,sy,45,0.95,"#C2343F")}</g>'
out['A6']=svg(BLUE,t+arc(x0+60,y0+230,150,70,BLUE)+st+'</g>')
for k,v in out.items(): open(k+'.svg','w').write(v)

S=400;G=40
names={'A1':'Klasik','A2':'Dört kategori','A3':'Açık tema','A4':'Birleşme anı','A5':'S birleşim','A6':'Damgalı'}
RH=S+60+150+G; WW=3*S+4*G; HH=2*RH+G
o=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{WW}" height="{WW}" viewBox="0 0 {WW} {WW}"><rect width="{WW}" height="{WW}" fill="#F5F5F5"/>']
for i,k in enumerate(names):
    x=G+(i%3)*(S+G); y=G+(i//3)*RH
    for sz,px,py in [(S,x,y),(128,x+S/2-150,y+S+80),(60,x+S/2+40,y+S+80)]:
        o.append(f'<clipPath id="q{k}{sz}"><rect x="{px}" y="{py}" width="{sz}" height="{sz}" rx="{sz*0.2237:.0f}"/></clipPath><g clip-path="url(#q{k}{sz})"><image href="{k}.svg.png" x="{px}" y="{py}" width="{sz}" height="{sz}"/></g>')
    o.append(f'<text x="{x+S/2}" y="{y+S+52}" text-anchor="middle" font-family="-apple-system" font-size="30" font-weight="600" fill="#1C1D21">{k} · {names[k]}</text>')
o.append('</svg>'); open('sheetA.svg','w').write(''.join(o))
