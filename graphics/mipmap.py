from PIL import Image
import os, math
from pathlib import Path

def crop_canvas(old_image, size):
  old_image = old_image.crop(old_image.getbbox())
  old_width, old_height = old_image.size
  if old_width > size or old_height > size:
    largest = (old_width >= old_height) and old_width or old_height
    old_image = old_image.resize((int(size*old_width/largest),int(size*old_height/largest)), Image.LANCZOS)
    old_width, old_height = old_image.size
  x1 = int(math.floor((size - old_width) / 2))
  y1 = int(math.floor((size - old_height) / 2))
  newImage = Image.new("RGBA", (size, size), (0,0,0,0))
  newImage.paste(old_image, (x1, y1, x1 + old_width, y1 + old_height))
  return newImage

def create_mipmap(outputf, inputf, size, levels):
  original = crop_canvas(Image.open(inputf),size)
  mipmap = Image.new("RGBA", (int(size * ((1-0.5**levels)/0.5)), size), (0,0,0,0))
  offset = 0
  for i in range(0,levels):
    new_size = int(size * (0.5**i))
    copy = original.resize((new_size, new_size), Image.LANCZOS)
    mipmap.paste(copy, box = (offset, 0))
    offset += new_size
  mipmap.save(outputf)  

finput = "./source/"
foutput = "./"
max_icon_size = 256
mipmap_levels = 4

for dirpath, dirs, files in os.walk(finput):
    for filename in files:
        if ".png" in filename:
          print(filename)
          create_mipmap(foutput+filename, finput+filename, max_icon_size, mipmap_levels)
