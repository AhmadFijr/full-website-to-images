async function mouse_click_event(element) {
  if (element) {
    try {
      element.scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      });
      await delay(100); // Small delay after scrolling
      element.click();
      console.log('Clicked on element:', element);
    } catch (error) {
      console.error('Error clicking on element:', element, error);
    }
  } else {
    console.error('Element not found for clicking.');
  }
}

async function changeInputValue(selector, value) {
  try {
    const element = await waitForElement(selector);
    if (element) {
      element.value = value;
      // Trigger input and change events to simulate user typing
      element.dispatchEvent(new Event('input', {
        bubbles: true
      }));
      element.dispatchEvent(new Event('change', {
        bubbles: true
      }));
      console.log(`Input value changed for selector "${selector}" to "${value}"`);
    } else {
      console.error(`Element with selector "${selector}" not found for input change.`);
    }
  } catch (error) {
    console.error(`Error changing input value for selector "${selector}":`, error);
  }
}

function waitForElement(selector, timeout = 10000) {
  return new Promise((resolve, reject) => {
    const startTime = Date.now();

    const checkElement = () => {
      const element = document.querySelector(selector);
      if (element) {
        resolve(element);
      } else if (Date.now() - startTime >= timeout) {
        reject(new Error(`Element with selector "${selector}" not found within timeout.`));
      } else {
        setTimeout(checkElement, 100);
      }
    };

    checkElement();
  });
}

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function sleep(ms) {
  console.log(`Sleeping for ${ms}ms...`);
  await delay(ms);
  console.log('Sleep finished.');
}