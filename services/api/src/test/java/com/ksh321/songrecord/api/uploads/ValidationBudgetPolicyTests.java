package com.ksh321.songrecord.api.uploads;
import org.junit.jupiter.api.Test;
import java.util.concurrent.*;
import static org.assertj.core.api.Assertions.*;
class ValidationBudgetPolicyTests {
 @Test void loweredWorkerSlotAndDeadlineAreSharedByNestedStagesAndOtherThreads()throws Exception {
  ValidationBudget.configure(1,1);
  try {
   try(var budget=ValidationBudget.enter();var nested=ValidationBudget.enter()){
    assertThat(budget.remaining()).isLessThanOrEqualTo(TimeUnit.SECONDS.toNanos(1));assertThat(nested.deadline()).isEqualTo(budget.deadline());
    try(var pool=Executors.newSingleThreadExecutor()){assertThat(pool.submit(()->{try(var other=ValidationBudget.enter()){return "ACQUIRED";}catch(java.io.IOException e){return e.getMessage();}}).get(5,TimeUnit.SECONDS)).isEqualTo("UPLOAD_WORKER_BUSY");}
   }
   try(var next=ValidationBudget.enter()){assertThat(next.remaining()).isPositive();}
  }finally{ValidationBudget.configure(2,60);}
 }
}
