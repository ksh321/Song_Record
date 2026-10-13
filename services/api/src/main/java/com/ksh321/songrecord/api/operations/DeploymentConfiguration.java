package com.ksh321.songrecord.api.operations;

import org.springframework.context.annotation.*;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.core.env.Environment;

@Configuration(proxyBeanMethods=false) @Profile({"staging","prod"})
public class DeploymentConfiguration {
 @Bean static BeanFactoryPostProcessor deploymentBoundary(Environment environment){return factory->DeploymentBoundary.validate(environment);}
}
