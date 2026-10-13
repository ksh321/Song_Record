package com.ksh321.songrecord.api.operations;

import java.net.URI;
import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

/** Reject dangerous mixed deployment settings before accepting requests. Never prints values. */
public final class DeploymentBoundary {
 private DeploymentBoundary(){}
 public static void validate(Environment env){
  var name=env.getProperty("songrecord.deployment.environment","");
  if(!Set.of("staging","prod").contains(name)||!env.acceptsProfiles(Profiles.of(name)))throw invalid();
  if(env.acceptsProfiles(Profiles.of("dev","bootstrap","candidate-fixtures","test","development")))throw invalid();
  var origin=URI.create(required(env,"songrecord.deployment.public-origin"));
  if(!"https".equals(origin.getScheme())||origin.getHost()==null||origin.getUserInfo()!=null||origin.getRawQuery()!=null||origin.getRawFragment()!=null||!Set.of("","/").contains(origin.getPath()))throw invalid();
  if(name.equals("prod")&&(Set.of("localhost","127.0.0.1","::1").contains(origin.getHost())||origin.getHost().endsWith(".invalid")))throw invalid();
  if(!env.getProperty("server.ssl.enabled",Boolean.class,false)||!env.getProperty("spring.flyway.clean-disabled",Boolean.class,false))throw invalid();
  if(!"validate".equals(env.getProperty("spring.jpa.hibernate.ddl-auto"))||!env.getProperty("spring.flyway.validate-on-migrate",Boolean.class,false))throw invalid();
  if(!env.getProperty("songrecord.storage.enabled",Boolean.class,false))throw invalid();
  var role=required(env,"songrecord.storage.role");if(!Set.of("api","worker").contains(role))throw invalid();
  if(role.equals("api")&&(env.getProperty("songrecord.upload.scheduling-enabled",Boolean.class,false)||env.getProperty("songrecord.account-deletion.worker.enabled",Boolean.class,false)))throw invalid();
  var storage=required(env,"songrecord.storage.environment");if(!storage.equals(name.equals("staging")?"dev":"prod"))throw invalid();
  var prefix="songrecord.storage."+storage+".";
  var buckets=name.equals("staging")?"song-record-staging-dev-":"song-record-prod-";
  if(!required(env,prefix+"temporary-bucket").equals(buckets+"temporary")||!required(env,prefix+"final-bucket").equals(buckets+"final"))throw invalid();
  required(env,"DB_PASSWORD");required(env,"TLS_KEYSTORE_PASSWORD");
 }
 private static String required(Environment e,String k){var v=e.getProperty(k);if(v==null||v.isBlank())throw invalid();return v;}
 private static IllegalStateException invalid(){return new IllegalStateException("DEPLOYMENT_BOUNDARY_INVALID: inspect profile, HTTPS, database, storage isolation and role settings; values suppressed");}
}
