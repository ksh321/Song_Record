package com.ksh321.songrecord.api.operations;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import static org.assertj.core.api.Assertions.*;
class OperationsPolicyTests {
 @Test void explicitDeploymentOverridesRemainWithinSchemaAndRuntimeCeilings(){var e=new MockEnvironment().withProperty("songrecord.operations.beta-accounts","2").withProperty("songrecord.operations.daily-upload-bytes","100").withProperty("songrecord.operations.worker-concurrency","1").withProperty("songrecord.operations.worker-seconds","5");var p=OperationsPolicy.from(e);assertThat(p.betaAccounts()).isEqualTo(2);assertThat(p.dailyBytes()).isEqualTo(100);assertThat(p.workerConcurrency()).isEqualTo(1);assertThat(p.workerSeconds()).isEqualTo(5);assertThat(p.globalBytes()).isEqualTo(20000000000L);}
 @Test void unsupportedOrNegativeLimitsFailBeforeServing(){for(var key:new String[]{"beta-accounts","pinned-limit","daily-upload-bytes","urls-per-minute","upload-concurrency","worker-concurrency","worker-seconds","personal-bytes","global-bytes","temporary-bytes"})assertThatThrownBy(()->OperationsPolicy.from(new MockEnvironment().withProperty("songrecord.operations."+key,"-1"))).isInstanceOf(IllegalArgumentException.class);for(var key:new String[]{"upload-concurrency","worker-concurrency"})assertThatThrownBy(()->OperationsPolicy.from(new MockEnvironment().withProperty("songrecord.operations."+key,"3"))).isInstanceOf(IllegalArgumentException.class);}
}
