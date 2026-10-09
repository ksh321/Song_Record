package com.ksh321.songrecord.api.storage;
/** Private development-only stdin checker; emits a closed status set, never credentials. */
public final class R2CleanupProbe {
 public static void main(String[] args){var report=System.out;System.setOut(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));System.setErr(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));
  try{byte[] input=System.in.readNBytes(16385);if(input.length>16384)throw new IllegalArgumentException();var props=new java.util.Properties();props.load(new java.io.StringReader(new String(input,java.nio.charset.StandardCharsets.UTF_8)));java.util.Arrays.fill(input,(byte)0);
   if(!"dev".equals(props.getProperty("songrecord.storage.environment")) || !"worker".equals(props.getProperty("songrecord.storage.role")))throw new IllegalArgumentException();
   var env=new org.springframework.core.env.StandardEnvironment();env.getPropertySources().addFirst(new org.springframework.core.env.PropertiesPropertySource("private-input",props));
   try(var storage=new R2StorageConfiguration().r2Storage(env)){com.ksh321.songrecord.api.retention.CleanupDeletionDatabaseChecks.verifyReal(storage);}props.clear();report.println("cleanup.final=VERIFIED");
  }catch(Throwable error){report.println("cleanup.final=ERROR");System.exit(2);}
 }
}
