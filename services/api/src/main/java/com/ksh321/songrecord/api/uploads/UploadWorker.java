package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.jobs.*;
/** Retry transient transport/DB failures; terminate proven invalid uploads without repeated decoding. */
public final class UploadWorker {
 private final JobQueue jobs;private final UploadVerification verification;private final AudioValidator validator;private final UploadFinalization finalizer;private final UploadRecovery recovery;
 public UploadWorker(JobQueue jobs,UploadVerification verification,AudioValidator validator,UploadFinalization finalizer,UploadRecovery recovery){this.jobs=jobs;this.verification=verification;this.validator=validator;this.finalizer=finalizer;this.recovery=recovery;}
 public boolean runOnce(){recovery.expire();recovery.exhausted();var claim=jobs.claim(JobQueue.Type.UPLOAD_VERIFY);if(claim.isEmpty())return false;var lease=claim.get();
  try(var budget=ValidationBudget.enter()){
   var recovered=finalizer.recover(lease,validator);Runnable effects=recovered.isPresent()?recovered.get():verification.prepare(lease,validator.then(finalizer));budget.check();jobs.complete(lease,effects);
  }catch(AudioValidator.Invalid e){if(e.code.equals("FILE_SANDBOX_UNAVAILABLE") || e.code.equals("FILE_VALIDATOR_UNAVAILABLE") || e.code.equals("UPLOAD_WORKER_BUSY"))jobs.fail(lease,true);else recovery.failed(lease,e.code);}
  catch(java.io.IOException e){if("FILE_VALIDATION_TIMEOUT".equals(e.getMessage()) || "UPLOAD_TOO_LARGE".equals(e.getMessage()))recovery.failed(lease,e.getMessage());else jobs.fail(lease,true);}
  catch(IllegalStateException e){if(java.util.Set.of("UPLOAD_AUTHORITY_LOST","NOT_CLOUD_TARGET","UPLOAD_POLICY_CHANGED","FILE_SPEC_MISMATCH").contains(e.getMessage()))recovery.failed(lease,e.getMessage());else jobs.fail(lease,true);}
  catch(Exception e){if(e instanceof InterruptedException)Thread.currentThread().interrupt();jobs.fail(lease,true);}
  return true;
 }
}
