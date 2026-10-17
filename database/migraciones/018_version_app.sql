-- =============================================================================
-- 018 · Versión de la app (aviso de actualización)
-- =============================================================================
--   TCONFIGURACIONES   APPVERSIONULTIMA   número de compilación más nuevo publicado (el "+N" de pubspec.yaml):
--                                         la app con uno menor ofrece actualizar (se puede cerrar)
--                      APPVERSIONMINIMA   por debajo de este número la app OBLIGA a actualizar
--                      APPURLDESCARGA     de dónde se descarga (vacío = <PUBLIC_URL>/descargas/vallexpress.apk)
--                      APPNOVEDADES       texto corto con lo nuevo de la versión
-- Al publicar una APK nueva: subirla a deploy/descargas/vallexpress.apk y cambiar APPVERSIONULTIMA (y MINIMA si
-- la versión anterior ya no debe usarse).
-- =============================================================================

INSERT INTO TCONFIGURACIONES (CCONFIGURACION, VALOR, DESCRIPCION) VALUES
    ('APPVERSIONULTIMA', '1',  'Número de compilación más nuevo de la app (el +N de pubspec.yaml): las anteriores ofrecen actualizar'),
    ('APPVERSIONMINIMA', '1',  'Número de compilación mínimo: por debajo la app obliga a actualizar'),
    ('APPURLDESCARGA',   '""', 'Dónde se descarga la app (vacío = <PUBLIC_URL>/descargas/vallexpress.apk)'),
    ('APPNOVEDADES',     '""', 'Lo nuevo de la última versión (se muestra en el aviso de actualización)')
ON CONFLICT (CCONFIGURACION, FHASTA) DO NOTHING;
