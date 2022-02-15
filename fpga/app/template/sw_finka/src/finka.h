#ifndef __FINKA_H__
#define __FINKA_H__

#include "timer.h"
#include "prescaler.h"
#include "interrupt.h"
#include "gpio.h"
#include "uart.h"

#define GPIO_A    ((Gpio_Reg*)(0xF0000000))
#define TIMER_PRESCALER ((Prescaler_Reg*)0xF0020000)
#define TIMER_INTERRUPT ((InterruptCtrl_Reg*)0xF0020010)
#define TIMER_A ((Timer_Reg*)0xF0020040)
#define TIMER_B ((Timer_Reg*)0xF0020050)
#define UART      ((Uart_Reg*)(0xF0010000))
#define AXI_A    ((uint32_t *)(0xA0000000))

#endif /* __FINKA_H__ */
