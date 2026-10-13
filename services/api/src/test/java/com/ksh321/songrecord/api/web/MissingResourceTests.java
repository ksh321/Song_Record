package com.ksh321.songrecord.api.web;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.*;
import org.springframework.mock.web.MockServletContext;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static org.assertj.core.api.Assertions.*;

class MissingResourceTests {
 @Configuration @EnableWebMvc @Import(GlobalExceptionHandler.class)
 static class Config implements WebMvcConfigurer {
  @Override public void addResourceHandlers(ResourceHandlerRegistry registry){registry.addResourceHandler("/**").addResourceLocations("classpath:/static/");}
 }
 @Test void absentDevelopmentResourceIsNotAServerFailureAndDoesNotEchoTheUrl()throws Exception{
  try(var context=new AnnotationConfigWebApplicationContext()){
   context.setServletContext(new MockServletContext());context.register(Config.class);context.refresh();
   var mvc=MockMvcBuilders.webAppContextSetup(context).build();
   var response=mvc.perform(get("/api/dev/errors/sample").param("token","synthetic-private-query"))
     .andExpect(status().isNotFound()).andExpect(header().string("Cache-Control","no-store"))
     .andExpect(jsonPath("$.error.code").value("NOT_FOUND")).andExpect(jsonPath("$.error.retryable").value(false)).andReturn().getResponse();
   assertThat(response.getContentAsString()).doesNotContain("synthetic-private-query","/api/dev/errors/sample","NoResourceFoundException");
  }
 }
}
