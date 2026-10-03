import re
exec(open('a2.py').read().split("for k,v in out.items()")[0])
def icon(bg, panel, orange, ink, arcc, shade=0.16):
    t,x0,y0,pw=joined(512,512,620,450,-9,[panel,orange],'url(#g)',stub=0.64)
    t=t.replace('opacity="0.16"',f'opacity="{shade}"')
    circles=re.findall(r'<circle [^>]*fill="url\(#g\)"/>',t)
    for c in circles: t=t.replace(c,'')
    cut=''.join(c.replace('fill="url(#g)"','fill="#000"') for c in circles)
    head,body=t.split('>',1)
    t=f'{head}><mask id="cut" maskUnits="userSpaceOnUse" x="-200" y="-200" width="1424" height="1424"><rect x="-200" y="-200" width="1424" height="1424" fill="#fff"/>{cut}</mask><g mask="url(#cut)">{body}'
    sx=x0+pw; sy=y0+150
    stamp=f'<g transform="rotate(-16 {sx} {sy})"><circle cx="{sx}" cy="{sy}" r="94" fill="none" stroke="{ink}" stroke-width="16"/><circle cx="{sx}" cy="{sy}" r="69" fill="none" stroke="{ink}" stroke-width="7"/>{plane(sx,sy,45,1.05,ink)}</g>'
    a=f'<path d="M{x0+60} {y0+232} q 80 -72 160 0" fill="none" stroke="{arcc}" stroke-width="16" stroke-linecap="round" stroke-dasharray="4 28"/>'
    defs='<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1E2647"/><stop offset="1" stop-color="#3B4FB8"/></linearGradient>'
    back={'gradient':'<rect width="1024" height="1024" fill="url(#g)"/>','black':'<rect width="1024" height="1024" fill="#000"/>','white':'<rect width="1024" height="1024" fill="#fff"/>'}[bg]
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs>{defs}</defs>{back}{t}{a}{stamp}</g></g></svg>'
open('icon-light.svg','w').write(icon('gradient','#FFFFFF','#F2814A','#C2343F','#5B78EE'))
for bg in ('black','white'):
    open(f'icon-dark-{bg}.svg','w').write(icon(bg,'#DCDEE4','#F2814A','#E5484D','#7D95F2',0.22))
    open(f'icon-tinted-{bg}.svg','w').write(icon(bg,'#FFFFFF','#9A9A9A','#3C3C3C','#6E6E6E',0.18))
