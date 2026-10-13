package com.ksh321.songrecord.api.operations;
import java.util.UUID;
/** Request-private, typed projections. No raw bodies, headers or authentication objects. */
public final class OperationsContext {
 public enum Action { SONG_READ, RECORDING_SAVED, PLAYBACK_URL, SYNC, SEARCH, CHART, DELETE, PIN, PIN_REPLACE, OTHER, JOB_CLAIM, JOB_SUCCESS, JOB_RETRY, JOB_FAILURE, JOB_RENEW, JOB_DEFER }
 public enum Result { SUCCESS, FAILURE, PIN_LIMIT_REACHED, QUOTA_EXCEEDED, AUTH_DENIED, NOT_FOUND }
 public static final class Trace {public UUID actor,target;public Action activity;public Result failure;public Long syncBacklog;}
 private static final ThreadLocal<Trace> CURRENT=new ThreadLocal<>();
 public static Trace begin(){var trace=new Trace();CURRENT.set(trace);return trace;}
 public static void clear(){CURRENT.remove();}
 public static void actor(UUID value){var t=CURRENT.get();if(t!=null)t.actor=value;}
 public static void target(UUID value){var t=CURRENT.get();if(t!=null)t.target=value;}
 public static void activity(Action value){var t=CURRENT.get();if(t!=null)t.activity=value;}
 public static void syncBacklog(long value){var t=CURRENT.get();if(t!=null&&value>=0)t.syncBacklog=value;}
 public static Long syncBacklog(){var t=CURRENT.get();return t==null?null:t.syncBacklog;}
 public static void failure(String code){var t=CURRENT.get();if(t!=null)t.failure=switch(code){case "PIN_LIMIT_REACHED"->Result.PIN_LIMIT_REACHED;case "QUOTA_EXCEEDED"->Result.QUOTA_EXCEEDED;case "RESOURCE_NOT_FOUND"->Result.NOT_FOUND;case "AUTH_INVALID_SESSION"->Result.AUTH_DENIED;default->Result.FAILURE;};}
 public static Action route(String method,String path){
  if(path.startsWith("/v1/sync/"))return Action.SYNC;
  if(path.startsWith("/v1/karaoke/"))return Action.SEARCH;
  if(path.startsWith("/v1/charts/"))return Action.CHART;
  if(path.startsWith("/v1/pins/")&&path.endsWith("/replacement"))return Action.PIN_REPLACE;
  if(path.startsWith("/v1/pins"))return Action.PIN;
  if(path.endsWith("/playback-url"))return Action.PLAYBACK_URL;
  if(method.equals("DELETE")||path.endsWith("/trash")||path.startsWith("/v1/account/deletion"))return Action.DELETE;
  if(method.equals("GET")&&path.startsWith("/v1/songs"))return Action.SONG_READ;
  return Action.OTHER;
 }
 public static UUID targetFromPath(String path){for(String part:path.split("/"))try{var id=UUID.fromString(part);if(id.toString().equals(part))return id;}catch(IllegalArgumentException ignored){}return null;}
}
