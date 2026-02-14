#!/usr/bin/env python3
"""
Script para generar iconos de app correctamente ajustados desde logo.png
El logo se recorta a un círculo/blanco centrado para que se vea bien en iconos
"""

from PIL import Image, ImageDraw
import os
import sys

def create_app_icons():
    # Rutas
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    logo_path = os.path.join(base_dir, 'assets', 'images', 'logo.png')
    res_dir = os.path.join(base_dir, 'android', 'app', 'src', 'main', 'res')
    
    if not os.path.exists(logo_path):
        print(f"❌ No se encontró: {logo_path}")
        sys.exit(1)
    
    print(f"✅ Logo encontrado: {logo_path}")
    
    # Abrir logo
    logo = Image.open(logo_path)
    
    # Si tiene transparencia, convertir a RGBA
    if logo.mode != 'RGBA':
        logo = logo.convert('RGBA')
    
    # Tamaños de iconos Android
    icon_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    
    # Tamaños de foreground para adaptive icons
    foreground_sizes = {
        'drawable-mdpi': 108,
        'drawable-hdpi': 162,
        'drawable-xhdpi': 216,
        'drawable-xxhdpi': 324,
        'drawable-xxxhdpi': 432,
    }
    
    # Crear iconos redondos (launcher icons)
    for folder, size in icon_sizes.items():
        output_dir = os.path.join(res_dir, folder)
        os.makedirs(output_dir, exist_ok=True)
        
        # Crear icono cuadrado con fondo negro y logo centrado
        icon = create_rounded_icon(logo, size, bg_color=(0, 0, 0, 255))
        
        output_path = os.path.join(output_dir, 'ic_launcher.png')
        icon.save(output_path, 'PNG')
        print(f"✅ Creado: {output_path} ({size}x{size})")
    
    # Crear foregrounds para adaptive icons
    for folder, size in foreground_sizes.items():
        output_dir = os.path.join(res_dir, folder)
        os.makedirs(output_dir, exist_ok=True)
        
        # Crear foreground (solo logo, sin fondo, escalado al 70% del tamaño)
        foreground = create_foreground(logo, size)
        
        output_path = os.path.join(output_dir, 'ic_launcher_foreground.png')
        foreground.save(output_path, 'PNG')
        print(f"✅ Creado: {output_path} ({size}x{size})")
    
    print("\n🎉 ¡Iconos generados exitosamente!")
    print("📱 Ahora compila: flutter build apk --release")

def create_rounded_icon(logo, size, bg_color=(0, 0, 0, 255)):
    """Crear icono redondo con fondo y logo centrado"""
    # Crear imagen cuadrada con fondo
    icon = Image.new('RGBA', (size, size), bg_color)
    
    # Calcular tamaño del logo (80% del icono)
    logo_size = int(size * 0.8)
    
    # Redimensionar logo manteniendo proporción
    logo_resized = resize_maintain_aspect(logo, logo_size)
    
    # Centrar logo
    x = (size - logo_resized.width) // 2
    y = (size - logo_resized.height) // 2
    
    # Pegar logo
    icon.paste(logo_resized, (x, y), logo_resized)
    
    # Aplicar máscara circular opcional (descomentar si quieres iconos redondos)
    # icon = apply_circle_mask(icon)
    
    return icon

def create_foreground(logo, size):
    """Crear foreground para adaptive icon (solo logo, transparente alrededor)"""
    # Crear imagen transparente
    foreground = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Calcular tamaño del logo (60% del tamaño total para dejar margen)
    logo_size = int(size * 0.6)
    
    # Redimensionar logo
    logo_resized = resize_maintain_aspect(logo, logo_size)
    
    # Centrar
    x = (size - logo_resized.width) // 2
    y = (size - logo_resized.height) // 2
    
    # Pegar
    foreground.paste(logo_resized, (x, y), logo_resized)
    
    return foreground

def resize_maintain_aspect(image, max_size):
    """Redimensionar manteniendo proporción de aspecto"""
    # Obtener dimensiones
    width, height = image.size
    
    # Calcular ratio
    ratio = min(max_size / width, max_size / height)
    
    # Nuevas dimensiones
    new_width = int(width * ratio)
    new_height = int(height * ratio)
    
    # Redimensionar con alta calidad
    resized = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
    
    return resized

def apply_circle_mask(image):
    """Aplicar máscara circular a la imagen"""
    size = image.size[0]
    
    # Crear máscara circular
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size, size), fill=255)
    
    # Aplicar máscara
    output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    output.paste(image, (0, 0))
    output.putalpha(mask)
    
    return output

if __name__ == '__main__':
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("❌ Instalando Pillow...")
        os.system(f"{sys.executable} -m pip install Pillow")
        from PIL import Image, ImageDraw
    
    create_app_icons()
