package com.ksh321.songrecord.api.operations;

import org.springframework.context.annotation.*;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.core.env.Environment;

@Configuration(proxyBeanMethods=false) @Profile({"staging","prod"})
public class DeploymentConfiguration {
 @Bean static BeanFactoryPostProcessor deploymentBoundary(Environment environment){return factory->DeploymentBoundary.validate(environment);}
 @Bean @org.springframework.boot.sql.init.dependency.DependsOnDatabaseInitialization
 org.springframework.beans.factory.InitializingBean requireCostMonitor(org.springframework.jdbc.core.JdbcTemplate db){return ()->{if(db.update("UPDATE global_storage_usage SET cost_monitor_required=TRUE WHERE id=1")!=1)throw new IllegalStateException("COST_GATE_MISSING");};}
}
