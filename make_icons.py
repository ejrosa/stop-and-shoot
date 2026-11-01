from PIL import Image, ImageDraw
def icon(size, maskable=False, path=None):
    S=size*4
    bg=(18,22,30,255)
    im=Image.new("RGBA",(S,S),bg)
    d=ImageDraw.Draw(im)
    pad = int(S*0.22) if maskable else int(S*0.12)
    # pin shape: circle + triangle
    w=S-2*pad
    cx=S//2; r=int(w*0.36); cy=pad+int(w*0.40)
    orange=(255,138,36,255)
    d.polygon([(cx-int(r*0.86),cy+int(r*0.5)),(cx+int(r*0.86),cy+int(r*0.5)),(cx,pad+w)],fill=orange)
    d.ellipse([cx-r,cy-r,cx+r,cy+r],fill=orange)
    # camera lens
    lr=int(r*0.58); d.ellipse([cx-lr,cy-lr,cx+lr,cy+lr],fill=bg)
    lr2=int(r*0.36); d.ellipse([cx-lr2,cy-lr2,cx+lr2,cy+lr2],fill=(255,255,255,255))
    lr3=int(r*0.14); d.ellipse([cx-lr3,cy-lr3,cx+lr3,cy+lr3],fill=bg)
    im=im.resize((size,size),Image.LANCZOS)
    im.save(path)
icon(192,path="icons/icon-192.png")
icon(512,path="icons/icon-512.png")
icon(512,True,"icons/maskable-512.png")
icon(180,path="icons/apple-touch-icon.png")
icon(32,path="icons/favicon-32.png")
