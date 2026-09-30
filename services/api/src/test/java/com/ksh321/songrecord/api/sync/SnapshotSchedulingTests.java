package com.ksh321.songrecord.api.sync;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.scheduling.annotation.ScheduledAnnotationBeanPostProcessor;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class SnapshotSchedulingTests {
    ApplicationContextRunner runner(){return new ApplicationContextRunner().withUserConfiguration(SnapshotScheduling.class)
            .withBean(SnapshotWorker.class,()->mock(SnapshotWorker.class)).withBean(SnapshotCleanup.class,()->mock(SnapshotCleanup.class));}
    @Test void liveSchedulingRegistersBothTasksAndTestOptOutRegistersNeither(){
        runner().run(c->{assertThat(c).hasSingleBean(SnapshotScheduling.class);
            assertThat(c.getBean(ScheduledAnnotationBeanPostProcessor.class).getScheduledTasks()).hasSize(2);});
        runner().withPropertyValues("songrecord.snapshots.scheduling-enabled=false").run(c->assertThat(c).doesNotHaveBean(SnapshotScheduling.class));
        runner().withInitializer(c->c.getEnvironment().setActiveProfiles("bootstrap")).run(c->assertThat(c).doesNotHaveBean(SnapshotScheduling.class));
    }
    @Test void tickFailuresDoNotKillFutureExecution(){
        var worker=mock(SnapshotWorker.class);var cleanup=mock(SnapshotCleanup.class);
        when(worker.runOnce()).thenThrow(new IllegalStateException("synthetic")).thenReturn(false);
        when(cleanup.runOnce()).thenThrow(new IllegalStateException("synthetic")).thenReturn(0);
        var ticks=new SnapshotScheduling(worker,cleanup);ticks.build();ticks.clean();ticks.build();ticks.clean();
        verify(worker,times(2)).runOnce();verify(cleanup,times(2)).runOnce();
    }
}
