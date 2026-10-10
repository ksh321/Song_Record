package com.ksh321.songrecord.api.charts;
/** Shared monotonic budget across collection, staging and publication, never wall-clock guesses. */
final class ChartJobDeadline {
    static final ThreadLocal<Long> END=new ThreadLocal<>();
    static int transactionSeconds(){var end=END.get();if(end==null)return 10;long seconds=(end-System.nanoTime())/1_000_000_000L;if(seconds<1)throw new ChartCollection.CollectionFailure(ChartCollection.Failure.TIMEOUT);return (int)Math.min(10,seconds);}
    static void check(){var end=END.get();if(end!=null && System.nanoTime()>=end)throw new ChartCollection.CollectionFailure(ChartCollection.Failure.TIMEOUT);}
}
